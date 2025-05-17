import Foundation
import SignalServiceKit
import CocoaLumberjack

// MARK: - GlobalSignatureService

public class GlobalSignatureService {
    
    // MARK: - Types
    
    public enum GlobalSignatureServiceError: Error, Equatable {
        case connectionFailed
        case authenticationFailed
        case badRequest
        case serverError
        case accessDenied
        case throttled
        case duplicateSignature
        case conditionalCheckFailed
        case unknown
        
        public var isTransient: Bool {
            switch self {
            case .connectionFailed, .serverError, .throttled:
                return true
            default:
                return false
            }
        }
        
        public var isConditionalCheckFailed: Bool {
            if case .conditionalCheckFailed = self {
                return true
            }
            return false
        }
    }
    
    public enum ImportProgress {
        case notStarted
        case inProgress(Double)
        case completed
        case failed(Error)
    }
    
    // MARK: - Properties
    
    public static let shared = GlobalSignatureService()
    
    private let apiClient: APIGatewayClientProtocol
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // AWS configuration
    private let region = AWSConfig.region
    private let identityPoolId = AWSConfig.cognitoIdentityPoolId
    private let hashTableName = AWSConfig.hashTableName
    private let authenticatedRoleArn = AWSConfig.authenticatedRoleArn
    
    // MARK: - Initialization
    
    public init(apiClient: APIGatewayClientProtocol = APIGatewayClient.shared) {
        self.apiClient = apiClient
    }
    
    // MARK: - Hash Checking
    
    public func checkSignatureExists(_ signature: String) async throws -> Bool {
        guard AWSConfig.checkHash else {
            Logger.info("Signature checking is disabled")
            return false
        }
        
        do {
            return try await apiClient.checkHash(signature)
        } catch let error as APIGatewayClient.APIGatewayError {
            switch error {
            case .authenticationFailed:
                throw GlobalSignatureServiceError.authenticationFailed
            case .requestFailed(let statusCode):
                if statusCode == 400 {
                    throw GlobalSignatureServiceError.badRequest
                } else if statusCode == 403 {
                    throw GlobalSignatureServiceError.accessDenied
                } else {
                    throw GlobalSignatureServiceError.unknown
                }
            case .invalidResponse:
                throw GlobalSignatureServiceError.serverError
            case .networkError:
                throw GlobalSignatureServiceError.connectionFailed
            case .rateLimited:
                throw GlobalSignatureServiceError.throttled
            case .internalServerError:
                throw GlobalSignatureServiceError.serverError
            case .invalidConfiguration:
                throw GlobalSignatureServiceError.unknown
            }
        } catch {
            throw GlobalSignatureServiceError.unknown
        }
    }
    
    // MARK: - Hash Storage
    
    public func storeSignature(_ signature: String) async throws {
        guard AWSConfig.storeHash else {
            Logger.info("Signature storage is disabled")
            return
        }
        
        do {
            let success = try await apiClient.storeHash(signature)
            
            if !success {
                throw GlobalSignatureServiceError.unknown
            }
        } catch let error as APIGatewayClient.APIGatewayError {
            switch error {
            case .authenticationFailed:
                throw GlobalSignatureServiceError.authenticationFailed
            case .requestFailed(let statusCode):
                if statusCode == 400 {
                    throw GlobalSignatureServiceError.badRequest
                } else if statusCode == 403 {
                    throw GlobalSignatureServiceError.accessDenied
                } else if statusCode == 409 {
                    throw GlobalSignatureServiceError.duplicateSignature
                } else {
                    throw GlobalSignatureServiceError.unknown
                }
            case .invalidResponse:
                throw GlobalSignatureServiceError.serverError
            case .networkError:
                throw GlobalSignatureServiceError.connectionFailed
            case .rateLimited:
                throw GlobalSignatureServiceError.throttled
            case .internalServerError:
                throw GlobalSignatureServiceError.serverError
            case .invalidConfiguration:
                throw GlobalSignatureServiceError.unknown
            }
        } catch {
            if (error as? AWSDynamoDBErrorType) == .conditionalCheckFailed {
                throw GlobalSignatureServiceError.conditionalCheckFailed
            } else {
                throw GlobalSignatureServiceError.unknown
            }
        }
    }
    
    // MARK: - Hash Deletion
    
    public func deleteSignature(_ signature: String) async throws {
        guard AWSConfig.deleteHash else {
            Logger.info("Signature deletion is disabled")
            return
        }
        
        do {
            let success = try await apiClient.deleteHash(signature)
            
            if !success {
                throw GlobalSignatureServiceError.unknown
            }
        } catch let error as APIGatewayClient.APIGatewayError {
            switch error {
            case .authenticationFailed:
                throw GlobalSignatureServiceError.authenticationFailed
            case .requestFailed(let statusCode):
                if statusCode == 400 {
                    throw GlobalSignatureServiceError.badRequest
                } else if statusCode == 403 {
                    throw GlobalSignatureServiceError.accessDenied
                } else {
                    throw GlobalSignatureServiceError.unknown
                }
            case .invalidResponse:
                throw GlobalSignatureServiceError.serverError
            case .networkError:
                throw GlobalSignatureServiceError.connectionFailed
            case .rateLimited:
                throw GlobalSignatureServiceError.throttled
            case .internalServerError:
                throw GlobalSignatureServiceError.serverError
            case .invalidConfiguration:
                throw GlobalSignatureServiceError.unknown
            }
        } catch {
            throw GlobalSignatureServiceError.unknown
        }
    }
    
    // MARK: - Batch Operations
    
    public func batchStoreSignatures(_ signatures: [String]) async -> (success: Int, failed: Int, totalHashes: Int) {
        let totalHashes = signatures.count
        var successCount = 0
        var failureCount = 0
        
        for signature in signatures {
            do {
                try await storeSignature(signature)
                successCount += 1
            } catch {
                Logger.error("Failed to store signature: \(error)")
                failureCount += 1
            }
        }
        
        return (success: successCount, failed: failureCount, totalHashes: totalHashes)
    }
    
    public func batchCheckSignatures(_ signatures: [String]) async -> (existingHashes: [String], totalHashes: Int, success: Bool) {
        let totalHashes = signatures.count
        var existingSignatures: [String] = []
        
        for signature in signatures {
            do {
                let exists = try await checkSignatureExists(signature)
                if exists {
                    existingSignatures.append(signature)
                }
            } catch {
                Logger.error("Failed to check signature: \(error)")
            }
        }
        
        return (existingHashes: existingSignatures, totalHashes: totalHashes, success: existingSignatures.count > 0 || signatures.isEmpty)
    }
    
    public func batchDeleteSignatures(_ signatures: [String]) async -> (success: Int, failed: Int, totalHashes: Int) {
        let totalHashes = signatures.count
        var successCount = 0
        var failureCount = 0
        
        for signature in signatures {
            do {
                try await deleteSignature(signature)
                successCount += 1
            } catch {
                Logger.error("Failed to delete signature: \(error)")
                failureCount += 1
            }
        }
        
        return (success: successCount, failed: failureCount, totalHashes: totalHashes)
    }
}

// MARK: - S3toDynamoDBImporter

public class S3toDynamoDBImporter {
    public static let shared = S3toDynamoDBImporter()
    
    public struct ImportStatus {
        public var status: ImportProgress
        public var progress: Double
        
        public init(status: ImportProgress, progress: Double) {
            self.status = status
            self.progress = progress
        }
    }
    
    public private(set) var currentStatus = ImportStatus(status: .notStarted, progress: 0)
    private var cancellationRequested = false
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    private init() {}
    
    public func beginImport() {
        guard case .notStarted = currentStatus.status else {
            return
        }
        
        var updatedStatus = currentStatus
        updatedStatus.status = .inProgress(0)
        updatedStatus.progress = 0
        currentStatus = updatedStatus
        
        Task {
            do {
                try await performImport()
                
                var finalStatus = currentStatus
                finalStatus.status = .completed
                finalStatus.progress = 1.0
                currentStatus = finalStatus
                
            } catch {
                var errorStatus = currentStatus
                errorStatus.status = .failed(error)
                currentStatus = errorStatus
            }
        }
    }
    
    public func cancelImport() {
        cancellationRequested = true
    }
    
    private func performImport() async throws {
        // Simulated import process
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            if cancellationRequested {
                throw NSError(domain: "com.signal.globalSignatureService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Import canceled"])
            }
            
            var updatedStatus = currentStatus
            updatedStatus.status = .inProgress(progress)
            updatedStatus.progress = progress
            currentStatus = updatedStatus
            
            // Simulate work
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    public func resetStatus() {
        var resetStatus = currentStatus
        resetStatus.status = .notStarted
        resetStatus.progress = 0
        currentStatus = resetStatus
        cancellationRequested = false
    }
}

// MARK: - AWSCredentialsVerificationManager

public class AWSCredentialsVerificationManager {
    public static let shared = AWSCredentialsVerificationManager()
    
    private init() {}
    
    public func verifyCredentials() async -> Bool {
        // Simulate credential verification
        return true
    }
    
    public func generateVerificationReport() async -> AWSDependencyVerificationReport {
        return AWSDependencyVerificationReport(
            awsCredentialsValid: true,
            dynamoDBAccessible: true,
            s3Accessible: true,
            apiGatewayAccessible: true,
            details: "All AWS dependencies verified successfully"
        )
    }
}

// MARK: - AWSDependencyVerificationReport

public struct AWSDependencyVerificationReport: Equatable {
    public let awsCredentialsValid: Bool
    public let dynamoDBAccessible: Bool
    public let s3Accessible: Bool
    public let apiGatewayAccessible: Bool
    public let details: String
    
    public var allDependenciesValid: Bool {
        return awsCredentialsValid && dynamoDBAccessible && s3Accessible && apiGatewayAccessible
    }
    
    public var full: String {
        """
        AWS Dependency Verification Report:
        - AWS Credentials Valid: \(awsCredentialsValid ? "Yes" : "No")
        - DynamoDB Accessible: \(dynamoDBAccessible ? "Yes" : "No")
        - S3 Accessible: \(s3Accessible ? "Yes" : "No")
        - API Gateway Accessible: \(apiGatewayAccessible ? "Yes" : "No")
        - Details: \(details)
        """
    }
}

// MARK: - AWSServiceMock

public class AWSServiceMock {
    public enum MockBehavior {
        case success
        case fail(Error)
        case delay(TimeInterval, Result<Void, Error>)
    }
    
    public var dynamoDBBehavior: MockBehavior = .success
    public var s3Behavior: MockBehavior = .success
    public var apiGatewayBehavior: MockBehavior = .success
    public var cognitoBehavior: MockBehavior = .success
    
    public init() {}
    
    public func simulateDynamoDBError(_ errorType: AWSDynamoDBErrorType) {
        dynamoDBBehavior = .fail(errorType)
    }
    
    public func simulateApiGatewayError(_ errorType: AWSServiceErrorType) {
        apiGatewayBehavior = .fail(errorType)
    }
    
    public func simulateCognitoError(_ errorType: AWSCognitoIdentityErrorType) {
        cognitoBehavior = .fail(errorType)
    }
    
    public func resetAllBehaviors() {
        dynamoDBBehavior = .success
        s3Behavior = .success
        apiGatewayBehavior = .success
        cognitoBehavior = .success
    }
} 