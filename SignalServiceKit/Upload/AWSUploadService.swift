import Foundation
import AWSS3
import AWSDynamoDB
import SignalCoreKit
import Logging

/// A service that handles AWS S3 uploads and DynamoDB metadata storage.
/// This service manages file uploads to S3 and stores associated metadata in DynamoDB.
/// It includes retry logic, supports chunked uploads for large files, and handles duplicate detection.
class AWSUploadService {
    // MARK: - Properties
    
    private let s3Client: AWSS3
    private let dynamoDBClient: AWSDynamoDB
    private let logger: Logger
    private let chunkSize: Int64 = 5 * 1024 * 1024 // 5MB chunks
    
    // MARK: - Initialization
    
    /// Initializes the AWS upload service with configuration from AWSConfig.
    /// - Throws: `OWSAssertionError` if configuration is invalid
    init() throws {
        // Validate configuration
        try AWSConfig.validateConfiguration()
        
        // Ensure AWS credentials are set up
        if AWSServiceManager.default().defaultServiceConfiguration == nil {
            AWSConfig.setupAWSCredentials()
        }
        
        // Configure S3 client with custom timeouts and retry settings
        let s3Configuration = AWSS3ServiceConfiguration(
            region: AWSConfig.region,
            credentialsProvider: AWSServiceManager.default().defaultServiceConfiguration?.credentialsProvider
        )
        s3Configuration.timeoutIntervalForRequest = AWSConfig.requestTimeoutInterval
        s3Configuration.timeoutIntervalForResource = AWSConfig.resourceTimeoutInterval
        s3Configuration.maxRetryCount = UInt32(AWSConfig.maxRetryCount)
        
        // Register and get clients
        AWSS3.register(with: s3Configuration, forKey: "CustomS3Client")
        AWSDynamoDB.register(with: s3Configuration, forKey: "CustomDynamoDBClient")
        
        guard let s3Client = AWSS3(forKey: "CustomS3Client"),
              let dynamoDBClient = AWSDynamoDB(forKey: "CustomDynamoDBClient") else {
            throw OWSAssertionError("Failed to initialize AWS clients")
        }
        
        self.s3Client = s3Client
        self.dynamoDBClient = dynamoDBClient
        self.logger = Logger(label: "org.signal.AWSUploadService")
        
        logger.info("Initialized AWSUploadService with bucket: \(AWSConfig.s3Bucket)")
    }
    
    // MARK: - Public API
    
    /// Uploads a file to S3 and stores its metadata in DynamoDB.
    /// - Parameters:
    ///   - fileURL: The URL of the file to upload
    ///   - contentType: The MIME type of the file
    ///   - metadata: Additional metadata to store
    /// - Returns: The S3 key of the uploaded file
    /// - Throws: `AWSUploadError` if the upload fails
    func uploadFile(_ fileURL: URL, contentType: String, metadata: [String: String] = [:]) async throws -> String {
        // Calculate file hash
        let fileHash = try await calculateFileHash(fileURL)
        let s3Key = "\(AWSConfig.s3Prefix)\(fileHash)"
        
        // Check for duplicates
        if try await checkForDuplicate(fileHash) {
            logger.info("File with hash \(fileHash) already exists")
            return s3Key
        }
        
        // Upload to S3
        try await uploadToS3(fileURL: fileURL, s3Key: s3Key, contentType: contentType)
        
        // Store metadata in DynamoDB
        try await storeMetadata(s3Key: s3Key, fileHash: fileHash, metadata: metadata)
        
        return s3Key
    }
    
    // MARK: - Private Methods
    
    private func calculateFileHash(_ fileURL: URL) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        return data.sha256Hash.hexadecimalString
    }
    
    private func checkForDuplicate(_ fileHash: String) async throws -> Bool {
        let queryInput = AWSDynamoDBQueryInput()
        queryInput.tableName = AWSConfig.dynamoDBTable
        queryInput.keyConditionExpression = "file_hash = :hash"
        queryInput.expressionAttributeValues = [":hash": AWSDynamoDBAttributeValue(string: fileHash)]
        
        do {
            let result = try await dynamoDBClient.query(queryInput)
            return result.items?.count ?? 0 > 0
        } catch {
            logger.error("Failed to check for duplicate: \(error)")
            throw AWSUploadError.dynamoDBError(error)
        }
    }
    
    private func uploadToS3(fileURL: URL, s3Key: String, contentType: String) async throws {
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
        
        if fileSize <= chunkSize {
            // Single part upload for small files
            try await uploadSinglePart(fileURL: fileURL, s3Key: s3Key, contentType: contentType)
        } else {
            // Multipart upload for large files
            try await uploadMultipart(fileURL: fileURL, s3Key: s3Key, contentType: contentType, fileSize: fileSize)
        }
    }
    
    private func uploadSinglePart(fileURL: URL, s3Key: String, contentType: String) async throws {
        let uploadRequest = AWSS3PutObjectRequest()
        uploadRequest.bucket = AWSConfig.s3Bucket
        uploadRequest.key = s3Key
        uploadRequest.body = fileURL
        uploadRequest.contentType = contentType
        
        do {
            _ = try await s3Client.putObject(uploadRequest)
            logger.info("Successfully uploaded single part file: \(s3Key)")
        } catch {
            logger.error("Failed to upload single part file: \(error)")
            throw AWSUploadError.s3UploadError(error)
        }
    }
    
    private func uploadMultipart(fileURL: URL, s3Key: String, contentType: String, fileSize: Int64) async throws {
        // Initialize multipart upload
        let initRequest = AWSS3CreateMultipartUploadRequest()
        initRequest.bucket = AWSConfig.s3Bucket
        initRequest.key = s3Key
        initRequest.contentType = contentType
        
        guard let uploadId = try await s3Client.createMultipartUpload(initRequest).uploadId else {
            throw AWSUploadError.s3UploadError(NSError(domain: "AWSUploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize multipart upload"]))
        }
        
        // Upload parts
        var parts: [AWSS3CompletedPart] = []
        let totalParts = Int((fileSize + chunkSize - 1) / chunkSize)
        
        for partNumber in 1...totalParts {
            let partRequest = AWSS3UploadPartRequest()
            partRequest.bucket = AWSConfig.s3Bucket
            partRequest.key = s3Key
            partRequest.partNumber = NSNumber(value: partNumber)
            partRequest.uploadId = uploadId
            
            let startByte = Int64(partNumber - 1) * chunkSize
            let endByte = min(startByte + chunkSize, fileSize)
            let partData = try Data(contentsOf: fileURL, offset: startByte, length: Int(endByte - startByte))
            
            partRequest.body = partData
            
            do {
                let result = try await s3Client.uploadPart(partRequest)
                let completedPart = AWSS3CompletedPart()
                completedPart.partNumber = NSNumber(value: partNumber)
                completedPart.eTag = result.eTag
                parts.append(completedPart)
                
                logger.info("Uploaded part \(partNumber)/\(totalParts) for \(s3Key)")
            } catch {
                // Abort multipart upload on failure
                try? await s3Client.abortMultipartUpload(AWSS3AbortMultipartUploadRequest(bucket: AWSConfig.s3Bucket, key: s3Key, uploadId: uploadId))
                throw AWSUploadError.s3UploadError(error)
            }
        }
        
        // Complete multipart upload
        let completeRequest = AWSS3CompleteMultipartUploadRequest()
        completeRequest.bucket = AWSConfig.s3Bucket
        completeRequest.key = s3Key
        completeRequest.uploadId = uploadId
        completeRequest.multipartUpload = AWSS3CompletedMultipartUpload()
        completeRequest.multipartUpload.parts = parts
        
        do {
            _ = try await s3Client.completeMultipartUpload(completeRequest)
            logger.info("Successfully completed multipart upload: \(s3Key)")
        } catch {
            throw AWSUploadError.s3UploadError(error)
        }
    }
    
    private func storeMetadata(s3Key: String, fileHash: String, metadata: [String: String]) async throws {
        let item = AWSDynamoDBPutItemInput()
        item.tableName = AWSConfig.dynamoDBTable
        
        var attributes: [String: AWSDynamoDBAttributeValue] = [
            "file_hash": AWSDynamoDBAttributeValue(string: fileHash),
            "s3_key": AWSDynamoDBAttributeValue(string: s3Key),
            "upload_timestamp": AWSDynamoDBAttributeValue(string: ISO8601DateFormatter().string(from: Date()))
        ]
        
        // Add custom metadata
        for (key, value) in metadata {
            attributes[key] = AWSDynamoDBAttributeValue(string: value)
        }
        
        item.item = attributes
        
        do {
            _ = try await dynamoDBClient.putItem(item)
            logger.info("Successfully stored metadata for file: \(s3Key)")
        } catch {
            logger.error("Failed to store metadata: \(error)")
            throw AWSUploadError.dynamoDBError(error)
        }
    }
}

// MARK: - Error Types

enum AWSUploadError: Error {
    case s3UploadError(Error)
    case dynamoDBError(Error)
    case invalidConfiguration(String)
    
    var localizedDescription: String {
        switch self {
        case .s3UploadError(let error):
            return "S3 upload failed: \(error.localizedDescription)"
        case .dynamoDBError(let error):
            return "DynamoDB operation failed: \(error.localizedDescription)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
} 