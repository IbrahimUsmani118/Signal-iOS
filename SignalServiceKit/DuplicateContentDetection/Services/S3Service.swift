import Foundation
import SignalServiceKit
import CocoaLumberjack

// MARK: - AWSS3 Error Types

/// Error thrown by AWS S3 service
public enum AWSS3ErrorType: String, Error {
    case authorizationHeaderMalformed = "AuthorizationHeaderMalformed"
    case badRequest = "BadRequest"
    case entityTooSmall = "EntityTooSmall"
    case entityTooLarge = "EntityTooLarge"
    case incorrectNumberOfFilesInPostRequest = "IncorrectNumberOfFilesInPostRequest"
    case invalidArgument = "InvalidArgument"
    case invalidBucketName = "InvalidBucketName"
    case invalidDigest = "InvalidDigest"
    case invalidEncryptionAlgorithmError = "InvalidEncryptionAlgorithmError"
    case invalidRange = "InvalidRange"
    case invalidToken = "InvalidToken"
    case keyTooLongError = "KeyTooLongError"
    case malformedXML = "MalformedXML"
    case metadata = "Metadata"
    case missingContentLength = "MissingContentLength"
    case missingRequestBodyError = "MissingRequestBodyError"
    case missingSecurityHeader = "MissingSecurityHeader"
    case noSuchBucket = "NoSuchBucket"
    case noSuchKey = "NoSuchKey"
    case noSuchUpload = "NoSuchUpload"
    case notImplemented = "NotImplemented"
    case notSignedUp = "NotSignedUp"
    case operationAborted = "OperationAborted"
    case requestIsNotMultiPartContent = "RequestIsNotMultiPartContent"
    case requestTimeout = "RequestTimeout"
    case requestTimeTooSkewed = "RequestTimeTooSkewed"
    case serviceUnavailable = "ServiceUnavailable"
    case signatureDoesNotMatch = "SignatureDoesNotMatch"
    case slowDown = "SlowDown"
    case temporaryRedirect = "TemporaryRedirect"
    case tooManyBuckets = "TooManyBuckets"
    case unexpectedContent = "UnexpectedContent"
    case userKeyMustBeSpecified = "UserKeyMustBeSpecified"
    case internalError = "InternalError"
    case unknown = "UnknownException"
}

/// HTTP method for AWS requests
public enum AWSHTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case HEAD
    
    var stringValue: String {
        return rawValue
    }
}

/// S3 server side encryption options
public enum AWSS3ServerSideEncryption: String {
    case aes256 = "AES256"
    case kms = "aws:kms"
}

// MARK: - S3Service

public class S3Service {
    
    // MARK: - Types
    
    public enum S3ServiceError: Error {
        case authenticationFailed
        case bucketNotFound
        case objectNotFound
        case requestFailed(String)
        case invalidResponse
        case connectionFailed
        case throttled
        case serverError
        case invalidConfiguration
        case uploadError(Error?)
        case downloadError(Error?)
        case deleteError(Error?)
        case presignedURLError(Error?)
    }
    
    // MARK: - Properties
    
    public static let shared = S3Service()
    
    private let region: String
    private let endpoint: String
    private let session: URLSession
    private var authToken: String?
    private var authTokenExpiration: Date?
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // MARK: - Initialization
    
    private init() {
        self.region = AWSConfig.region
        self.endpoint = "https://s3.\(region).amazonaws.com"
        self.session = URLSession.shared
    }
    
    // MARK: - Authentication
    
    private func authenticate() async throws -> String {
        // For actual impl, this would use AWS SDK
        // Simplified version that returns a dummy token
        if let token = authToken, let expiration = authTokenExpiration, expiration > Date() {
            return token
        }
        
        // In a real implementation, this would request a token from AWS Cognito
        authToken = "dummy-s3-auth-token"
        authTokenExpiration = Date().addingTimeInterval(3600) // 1 hour
        
        guard let token = authToken else {
            throw S3ServiceError.authenticationFailed
        }
        
        return token
    }
    
    // MARK: - S3 Operations
    
    /// Uploads a file to S3
    /// - Parameters:
    ///   - fileData: Data to upload
    ///   - key: S3 object key
    ///   - contentType: MIME type of the file
    ///   - metadata: Optional metadata to attach to the object
    /// - Returns: ETag of the uploaded object
    public func uploadFile(
        fileData: Data,
        key: String,
        contentType: String,
        metadata: [String: String]? = nil
    ) async throws -> String {
        let token = try await authenticate()
        let bucketName = AWSConfig.hashTableName + "-files"
        let endpoint = "\(self.endpoint)/\(bucketName)/\(key)"
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")
        request.setValue(AWSS3ServerSideEncryption.aes256.rawValue, forHTTPHeaderField: "x-amz-server-side-encryption")
        
        // Add metadata headers if provided
        metadata?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: "x-amz-meta-\(key)")
        }
        
        request.httpBody = fileData
        request.timeoutInterval = AWSConfig.requestTimeoutSeconds
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Invalid response type")
                throw S3ServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                if let etag = httpResponse.allHeaderFields["ETag"] as? String {
                    return etag
                } else {
                    Logger.warn("No ETag in response")
                    return "unknown-etag"
                }
            case 400:
                Logger.error("Bad request to S3")
                throw S3ServiceError.requestFailed("Bad request")
            case 401, 403:
                Logger.error("Authentication failed when accessing S3")
                throw S3ServiceError.authenticationFailed
            case 404:
                Logger.error("Bucket not found: \(bucketName)")
                throw S3ServiceError.bucketNotFound
            case 429:
                Logger.warn("S3 request throttled")
                throw S3ServiceError.throttled
            case 500...599:
                Logger.error("Server error during S3 upload: \(httpResponse.statusCode)")
                throw S3ServiceError.serverError
            default:
                Logger.error("Unexpected status code from S3: \(httpResponse.statusCode)")
                throw S3ServiceError.requestFailed("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as S3ServiceError {
            throw error
        } catch {
            Logger.error("Connection failed during S3 upload: \(error)")
            throw S3ServiceError.connectionFailed
        }
    }
    
    /// Downloads a file from S3
    /// - Parameters:
    ///   - key: S3 object key
    ///   - bucketName: Optional bucket name (defaults to config)
    /// - Returns: Downloaded file data
    public func downloadFile(
        key: String,
        bucketName: String? = nil
    ) async throws -> Data {
        let token = try await authenticate()
        let bucket = bucketName ?? AWSConfig.hashTableName + "-files"
        let endpoint = "\(self.endpoint)/\(bucket)/\(key)"
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = AWSConfig.requestTimeoutSeconds
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Invalid response type")
                throw S3ServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return data
            case 400:
                Logger.error("Bad request to S3")
                throw S3ServiceError.requestFailed("Bad request")
            case 401, 403:
                Logger.error("Authentication failed when accessing S3")
                throw S3ServiceError.authenticationFailed
            case 404:
                Logger.error("Object or bucket not found: \(key)")
                throw S3ServiceError.objectNotFound
            case 429:
                Logger.warn("S3 request throttled")
                throw S3ServiceError.throttled
            case 500...599:
                Logger.error("Server error during S3 download: \(httpResponse.statusCode)")
                throw S3ServiceError.serverError
            default:
                Logger.error("Unexpected status code from S3: \(httpResponse.statusCode)")
                throw S3ServiceError.requestFailed("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as S3ServiceError {
            throw error
        } catch {
            Logger.error("Connection failed during S3 download: \(error)")
            throw S3ServiceError.connectionFailed
        }
    }
    
    /// Checks if an object exists in S3
    /// - Parameters:
    ///   - key: S3 object key
    ///   - bucketName: Optional bucket name (defaults to config)
    /// - Returns: Whether the object exists
    public func doesObjectExist(
        key: String,
        bucketName: String? = nil
    ) async throws -> Bool {
        let token = try await authenticate()
        let bucket = bucketName ?? AWSConfig.hashTableName + "-files"
        let endpoint = "\(self.endpoint)/\(bucket)/\(key)"
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = AWSConfig.requestTimeoutSeconds
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Invalid response type")
                throw S3ServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                return true
            case 404:
                return false
            case 400:
                Logger.error("Bad request to S3")
                throw S3ServiceError.requestFailed("Bad request")
            case 401, 403:
                Logger.error("Authentication failed when accessing S3")
                throw S3ServiceError.authenticationFailed
            case 429:
                Logger.warn("S3 request throttled")
                throw S3ServiceError.throttled
            case 500...599:
                Logger.error("Server error during S3 HEAD request: \(httpResponse.statusCode)")
                throw S3ServiceError.serverError
            default:
                Logger.error("Unexpected status code from S3: \(httpResponse.statusCode)")
                throw S3ServiceError.requestFailed("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as S3ServiceError {
            throw error
        } catch {
            Logger.error("Connection failed during S3 HEAD request: \(error)")
            throw S3ServiceError.connectionFailed
        }
    }
    
    /// Generates a pre-signed URL for accessing an S3 object
    /// - Parameters:
    ///   - key: S3 object key
    ///   - bucketName: Optional bucket name (defaults to config)
    ///   - expires: URL expiration time in seconds
    ///   - httpMethod: HTTP method for the URL
    /// - Returns: Pre-signed URL
    public func getPresignedURL(
        key: String,
        bucketName: String? = nil,
        expires: TimeInterval = 3600,
        httpMethod: AWSHTTPMethod = .GET
    ) async throws -> URL {
        let token = try await authenticate()
        let bucket = bucketName ?? AWSConfig.hashTableName + "-files"
        
        // This is a simplified version. In a real implementation, this would use AWS SDK to generate a proper pre-signed URL
        let endpoint = "\(self.endpoint)/\(bucket)/\(key)"
        let baseURL = URL(string: endpoint)!
        
        // Create URL components for query parameters
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        
        // Add required query parameters for pre-signed URL
        let expiryTime = Int(Date().timeIntervalSince1970 + expires)
        let queryItems = [
            URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
            URLQueryItem(name: "X-Amz-Credential", value: "DUMMY_CREDENTIAL"),
            URLQueryItem(name: "X-Amz-Date", value: ISO8601DateFormatter().string(from: Date())),
            URLQueryItem(name: "X-Amz-Expires", value: "\(Int(expires))"),
            URLQueryItem(name: "X-Amz-SignedHeaders", value: "host"),
            URLQueryItem(name: "X-Amz-Signature", value: "DUMMY_SIGNATURE_\(token)_\(expiryTime)_\(httpMethod.stringValue)")
        ]
        
        components.queryItems = queryItems
        
        guard let signedURL = components.url else {
            throw S3ServiceError.presignedURLError(nil)
        }
        
        return signedURL
    }
    
    /// Deletes an object from S3
    /// - Parameters:
    ///   - key: S3 object key
    ///   - bucketName: Optional bucket name (defaults to config)
    public func deleteObject(
        key: String,
        bucketName: String? = nil
    ) async throws {
        let token = try await authenticate()
        let bucket = bucketName ?? AWSConfig.hashTableName + "-files"
        let endpoint = "\(self.endpoint)/\(bucket)/\(key)"
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = AWSConfig.requestTimeoutSeconds
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Invalid response type")
                throw S3ServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return
            case 400:
                Logger.error("Bad request to S3")
                throw S3ServiceError.requestFailed("Bad request")
            case 401, 403:
                Logger.error("Authentication failed when accessing S3")
                throw S3ServiceError.authenticationFailed
            case 404:
                // Object not found is not an error for delete operation
                Logger.info("Object already deleted or not found: \(key)")
                return
            case 429:
                Logger.warn("S3 request throttled")
                throw S3ServiceError.throttled
            case 500...599:
                Logger.error("Server error during S3 delete: \(httpResponse.statusCode)")
                throw S3ServiceError.serverError
            default:
                Logger.error("Unexpected status code from S3: \(httpResponse.statusCode)")
                throw S3ServiceError.requestFailed("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as S3ServiceError {
            throw error
        } catch {
            Logger.error("Connection failed during S3 delete: \(error)")
            throw S3ServiceError.connectionFailed
        }
    }
    
    // MARK: - Batch Operations
    
    /// Uploads multiple files to S3
    /// - Parameter files: Dictionary mapping file keys to their data
    /// - Returns: Dictionary mapping keys to ETags
    public func batchUpload(
        files: [String: Data]
    ) async -> [String: String] {
        var results: [String: String] = [:]
        
        for (key, data) in files {
            do {
                let etag = try await uploadFile(
                    fileData: data,
                    key: key,
                    contentType: "application/octet-stream"
                )
                results[key] = etag
            } catch {
                Logger.error("Failed to upload file \(key): \(error)")
            }
        }
        
        return results
    }
    
    /// Batch operation for downloading multiple files
    /// - Parameter keys: Array of object keys to download
    /// - Returns: Dictionary mapping keys to their data
    public func batchDownload(
        keys: [String]
    ) async -> [String: Data] {
        var results: [String: Data] = [:]
        
        for key in keys {
            do {
                let data = try await downloadFile(key: key)
                results[key] = data
            } catch {
                Logger.error("Failed to download file \(key): \(error)")
            }
        }
        
        return results
    }
    
    /// Uploads data from a local file to S3
    /// - Parameters:
    ///   - fileURL: Local file URL
    ///   - key: S3 object key
    ///   - contentType: MIME type of the file
    /// - Returns: ETag of the uploaded object
    public func uploadLocalFile(
        fileURL: URL,
        key: String,
        contentType: String
    ) async throws -> String {
        do {
            let data = try Data(contentsOf: fileURL)
            return try await uploadFile(
                fileData: data,
                key: key,
                contentType: contentType
            )
        } catch {
            Logger.error("Failed to read local file: \(error)")
            throw S3ServiceError.uploadError(error)
        }
    }
    
    // MARK: - Error Handling
    
    /// Determines if an S3 error is transient (can be retried)
    /// - Parameter error: Error to check
    /// - Returns: Whether the error is transient
    public func isTransientError(_ error: Error) -> Bool {
        if let serviceError = error as? AWSServiceErrorType {
            return [.throttlingException, .serviceUnavailable, .internalServerError].contains { $0 == serviceError }
        } else if let s3Error = error as? AWSS3ErrorType {
            return [.serviceUnavailable, .slowDown, .internalError, .requestTimeout].contains { $0 == s3Error }
        } else if let s3ServiceError = error as? S3ServiceError {
            switch s3ServiceError {
            case .throttled, .connectionFailed, .serverError:
                return true
            default:
                return false
            }
        }
        
        return false
    }
}

// MARK: - Additional Extension for Task compatibility

/// Helper function to wait for an async task and return its result
public func awaitResult<T>(_ work: () async throws -> T) async throws -> T {
    return try await work()
} 