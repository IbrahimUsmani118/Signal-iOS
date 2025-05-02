import Foundation
import AWSCore
import AWSS3
import AWSDynamoDB
import Logging
import CommonCrypto

/// Manages content uploads to S3 and duplicate detection using DynamoDB
public final class ContentUploadManager {
    public static let shared = ContentUploadManager()
    
    private let s3TransferUtility: AWSS3TransferUtility
    private let dynamoDB: AWSDynamoDB
    private let logger = Logging.Logger(label: "ContentUploadManager")
    
    private init() {
        // Get configured S3 transfer utility
        guard let transferUtility = AWSS3TransferUtility.s3TransferUtility(forKey: "default") else {
            fatalError("Failed to initialize S3 transfer utility")
        }
        self.s3TransferUtility = transferUtility
        
        // Get configured DynamoDB client
        guard let dynamoDB = AWSDynamoDB(forKey: "DynamoDB") else {
            fatalError("Failed to initialize DynamoDB client")
        }
        self.dynamoDB = dynamoDB
    }
    
    /// Uploads content to S3 and stores its signature in DynamoDB
    /// - Parameters:
    ///   - data: The content data to upload
    ///   - contentType: The MIME type of the content
    ///   - completion: Completion handler with the S3 key if successful, or error if failed
    public func uploadContent(_ data: Data, contentType: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Generate content hash for duplicate detection
        let contentHash = data.sha256().base64EncodedString()
        
        // Check for duplicates in DynamoDB
        checkForDuplicate(hash: contentHash) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let isDuplicate):
                if isDuplicate {
                    self.logger.info("Content already exists in global database")
                    completion(.failure(ContentUploadError.duplicateContent))
                    return
                }
                
                // Generate unique S3 key
                let s3Key = "\(AWSConfig.s3ImagesPath)\(UUID().uuidString)"
                
                // Upload to S3
                self.uploadToS3(data: data, key: s3Key, contentType: contentType) { uploadResult in
                    switch uploadResult {
                    case .success:
                        // Store signature in DynamoDB
                        self.storeSignature(hash: contentHash, s3Key: s3Key) { storeResult in
                            switch storeResult {
                            case .success:
                                completion(.success(s3Key))
                            case .failure(let error):
                                self.logger.error("Failed to store signature: \(error.localizedDescription)")
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        self.logger.error("Failed to upload to S3: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                self.logger.error("Failed to check for duplicates: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// Checks if content with the given hash already exists in DynamoDB
    private func checkForDuplicate(hash: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let input = AWSDynamoDBGetItemInput()!
        input.tableName = AWSConfig.dynamoDBTableName
        
        let hashAttr = AWSDynamoDBAttributeValue()!
        hashAttr.s = hash
        input.key = ["signature": hashAttr]
        
        dynamoDB.getItem(input).continueWith { task in
            if let error = task.error {
                completion(.failure(error))
            } else {
                let isDuplicate = (task.result?.item?.isEmpty == false)
                completion(.success(isDuplicate))
            }
            return nil
        }
    }
    
    /// Uploads data to S3
    private func uploadToS3(data: Data, key: String, contentType: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let expression = AWSS3TransferUtilityUploadExpression()
        expression.setValue("public-read", forRequestHeader: "x-amz-acl")
        
        s3TransferUtility.uploadData(
            data,
            bucket: AWSConfig.s3BucketName,
            key: key,
            contentType: contentType,
            expression: expression
        ) { task, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// Stores content signature in DynamoDB
    private func storeSignature(hash: String, s3Key: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let input = AWSDynamoDBPutItemInput()!
        input.tableName = AWSConfig.dynamoDBTableName
        
        let hashAttr = AWSDynamoDBAttributeValue()!
        hashAttr.s = hash
        
        let s3KeyAttr = AWSDynamoDBAttributeValue()!
        s3KeyAttr.s = s3Key
        
        let timestampAttr = AWSDynamoDBAttributeValue()!
        timestampAttr.n = String(Date().timeIntervalSince1970)
        
        input.item = [
            "signature": hashAttr,
            "s3Key": s3KeyAttr,
            "timestamp": timestampAttr
        ]
        
        dynamoDB.putItem(input).continueWith { task in
            if let error = task.error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
            return nil
        }
    }
}

// MARK: - Error Types
public enum ContentUploadError: Error {
    case duplicateContent
    case uploadFailed
    case storageFailed
}

// MARK: - Data Extension
extension Data {
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash)
    }
} 