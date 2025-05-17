import Foundation
import SignalServiceKit
import CocoaLumberjack

// MARK: - AWS Lambda Types

/// Enum that represents the invocation type for AWS Lambda
public enum LambdaInvocationType: String {
    case requestResponse = "RequestResponse"
    case event = "Event"
    case dryRun = "DryRun"
}

/// Status of a batch import job
public enum BatchJobStatus: String, Codable {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case canceled = "CANCELED"
}

/// Error thrown by AWS Lambda service
public enum AWSLambdaErrorType: String, Error {
    case serviceException = "ServiceException"
    case resourceNotFoundException = "ResourceNotFoundException"
    case invalidRequestContentException = "InvalidRequestContentException"
    case requestTooLargeException = "RequestTooLargeException"
    case unsupportedMediaTypeException = "UnsupportedMediaTypeException"
    case tooManyRequestsException = "TooManyRequestsException"
    case invalidParameterValueException = "InvalidParameterValueException"
    case ec2ThrottledException = "EC2ThrottledException"
    case ec2UnexpectedException = "EC2UnexpectedException"
    case kmsDisabledException = "KMSDisabledException"
    case kmsInvalidStateException = "KMSInvalidStateException"
    case kmsAccessDeniedException = "KMSAccessDeniedException"
    case kmsNotFoundException = "KMSNotFoundException"
    case efsioException = "EFSIOException"
    case efsMountConnectivityException = "EFSMountConnectivityException"
    case efsMountFailureException = "EFSMountFailureException"
    case efsMountTimeoutException = "EFSMountTimeoutException"
    case eniRequestLimitExceededException = "ENILimitReachedException"
    case subnetIPAddressLimitReachedException = "SubnetIPAddressLimitReachedException"
    case resourceNotReadyException = "ResourceNotReadyException"
    case unknownException = "UnknownException"
}

/// Job Status Data representing the status of a batch operation
public struct JobStatusData: Codable {
    public let jobId: String
    public let status: BatchJobStatus
    public let totalItems: Int
    public let processedItems: Int
    public let failedItems: Int
    public let messageDetails: String?
    public let startedAt: Date?
    public let completedAt: Date?
    
    public init(
        jobId: String,
        status: BatchJobStatus,
        totalItems: Int,
        processedItems: Int = 0,
        failedItems: Int = 0,
        messageDetails: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.totalItems = totalItems
        self.processedItems = processedItems
        self.failedItems = failedItems
        self.messageDetails = messageDetails
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

// MARK: - LambdaService

public class LambdaService {
    
    // MARK: - Types
    
    public enum LambdaServiceError: Error {
        case invocationFailed(String)
        case invalidResponse
        case serializationError
        case networkError(Error)
        case authenticationFailed
    }
    
    // MARK: - Properties
    
    public static let shared = LambdaService()
    
    private let session: URLSession
    private let region: String
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AWSConfig.requestTimeoutSeconds
        config.timeoutIntervalForResource = AWSConfig.resourceTimeoutSeconds
        self.session = URLSession(configuration: config)
        self.region = AWSConfig.dynamoDBRegion // Using same region for Lambda
    }
    
    // MARK: - Public Methods
    
    /// Invokes a Lambda function
    /// - Parameters:
    ///   - functionName: Name of the Lambda function
    ///   - payload: JSON payload for the function
    ///   - invocationType: Invocation type (RequestResponse, Event, or DryRun)
    /// - Returns: Response data
    public func invoke(
        functionName: String,
        payload: [String: Any],
        invocationType: String = "RequestResponse"
    ) async throws -> Data {
        let endpoint = "https://lambda.\(region).amazonaws.com/2015-03-31/functions/\(functionName)/invocations"
        
        guard let url = URL(string: endpoint) else {
            throw LambdaServiceError.invocationFailed("Invalid Lambda URL")
        }
        
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw LambdaServiceError.serializationError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payloadData
        request.setValue(invocationType, forHTTPHeaderField: "X-Amz-Invocation-Type")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add AWS auth headers if needed
        if !AWSConfig.accessKeyId.isEmpty && !AWSConfig.secretAccessKey.isEmpty {
            request.setValue(AWSConfig.accessKeyId, forHTTPHeaderField: "X-Amz-Security-Token")
            // In a real implementation, you would properly sign the request with AWS Signature v4
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LambdaServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return data
                
            case 401, 403:
                throw LambdaServiceError.authenticationFailed
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LambdaServiceError.invocationFailed("API error: \(httpResponse.statusCode), \(errorMessage)")
            }
        } catch let error as LambdaServiceError {
            throw error
        } catch {
            throw LambdaServiceError.networkError(error)
        }
    }
    
    /// Invokes a Lambda function asynchronously (fire and forget)
    /// - Parameters:
    ///   - functionName: Name of the Lambda function
    ///   - payload: JSON payload for the function
    public func invokeAsync(
        functionName: String,
        payload: [String: Any]
    ) async {
        do {
            _ = try await invoke(
                functionName: functionName,
                payload: payload,
                invocationType: "Event"
            )
        } catch {
            Logger.error("Async Lambda invocation failed: \(error)")
        }
    }
    
    /// Invokes the image tagging Lambda function
    /// - Parameter imageURL: URL of the image to tag
    /// - Returns: The image tag
    public func getImageTag(imageURL: URL) async throws -> String {
        let payload: [String: Any] = [
            "imageUrl": imageURL.absoluteString
        ]
        
        let data = try await invoke(
            functionName: "GetImageTag",
            payload: payload
        )
        
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = jsonResponse["tag"] as? String else {
            throw LambdaServiceError.invalidResponse
        }
        
        return tag
    }
    
    /// Invokes the image blocking Lambda function
    /// - Parameter imageURL: URL of the image to block
    /// - Returns: Success flag
    public func blockImage(imageURL: URL) async throws -> Bool {
        let payload: [String: Any] = [
            "imageUrl": imageURL.absoluteString
        ]
        
        let data = try await invoke(
            functionName: "BlockImage",
            payload: payload
        )
        
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool else {
            throw LambdaServiceError.invalidResponse
        }
        
        return success
    }
    
    // MARK: - Batch Job Operations
    
    /// Retrieves the status of a batch job
    /// - Parameter jobId: ID of the job to retrieve status for
    /// - Returns: Current status of the job
    public func getJobStatus(jobId: String) async throws -> JobStatusData {
        let payload = ["jobId": jobId]
        
        return try await invokeLambdaWithJson(
            functionName: AWSConfig.hashTableName + "-status",
            jsonPayload: payload,
            responseType: JobStatusData.self
        )
    }
    
    /// Starts a batch operation to store multiple hashes
    /// - Parameter hashes: Array of hash strings to store
    /// - Returns: Job status information
    public func batchStoreHashes(_ hashes: [String]) async throws -> JobStatusData {
        let payload = [
            "operation": "store",
            "hashes": hashes
        ]
        
        return try await invokeLambdaWithJson(
            functionName: AWSConfig.hashTableName + "-batch",
            jsonPayload: payload,
            responseType: JobStatusData.self
        )
    }
    
    /// Gets an updated progress report for a batch job
    /// - Parameter jobId: ID of the job to check progress for
    /// - Returns: Current progress of the job
    public func getBatchProgress(jobId: String) async throws -> JobStatusData {
        return try await getJobStatus(jobId: jobId)
    }
    
    /// Processes a batch of hashes
    /// - Parameters:
    ///   - hashes: Hashes to process
    ///   - operation: Operation to perform (check, store, delete)
    ///   - progressCallback: Callback for progress updates
    /// - Returns: Tuple containing success count, failure count, and total count
    public func processBatch(
        hashes: [String],
        operation: String,
        progressCallback: ((Double) -> Void)? = nil
    ) async throws -> (success: Int, failed: Int, totalHashes: Int) {
        let totalHashes = hashes.count
        
        let payload = [
            "operation": operation,
            "hashes": hashes
        ]
        
        do {
            let jobStatus = try await invokeLambdaWithJson(
                functionName: AWSConfig.hashTableName + "-batch",
                jsonPayload: payload,
                responseType: JobStatusData.self
            )
            
            var currentStatus = jobStatus
            var lastProgress: Double = 0
            
            while currentStatus.status == .pending || currentStatus.status == .inProgress {
                // Wait a bit before checking again
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                currentStatus = try await getJobStatus(jobId: currentStatus.jobId)
                
                let progress = Double(currentStatus.processedItems) / Double(totalHashes)
                if progress > lastProgress {
                    lastProgress = progress
                    progressCallback?(progress)
                }
            }
            
            if currentStatus.status == .completed {
                return (
                    success: currentStatus.processedItems - currentStatus.failedItems,
                    failed: currentStatus.failedItems,
                    totalHashes: totalHashes
                )
            } else {
                throw LambdaServiceError.invocationFailed("Job failed: \(currentStatus.messageDetails ?? "Unknown error")")
            }
        } catch {
            if let lambdaError = error as? LambdaServiceError {
                throw lambdaError
            } else {
                Logger.error("Error processing batch: \(error)")
                throw LambdaServiceError.unknownError(error)
            }
        }
    }
    
    // MARK: - Error Handling
    
    /// Determines if a Lambda error is transient (can be retried)
    /// - Parameter error: Error to check
    /// - Returns: Whether the error is transient
    public func isTransientError(_ error: Error) -> Bool {
        if let lambdaError = error as? AWSLambdaErrorType {
            switch lambdaError {
            case .serviceException, .tooManyRequestsException, .ec2ThrottledException,
                 .ec2UnexpectedException, .kmsDisabledException, .kmsInvalidStateException,
                 .kmsAccessDeniedException, .kmsNotFoundException, .efsioException,
                 .efsMountConnectivityException, .efsMountFailureException, .efsMountTimeoutException,
                 .eniRequestLimitExceededException, .subnetIPAddressLimitReachedException,
                 .resourceNotReadyException:
                return true
            default:
                return false
            }
        } else if let serviceError = error as? AWSServiceErrorType {
            switch serviceError {
            case .throttlingException, .serviceUnavailable, .internalServerError:
                return true
            default:
                return false
            }
        } else if let lambdaServiceError = error as? LambdaServiceError {
            switch lambdaServiceError {
            case .throttled, .connectionFailed, .serverError:
                return true
            default:
                return false
            }
        }
        
        return false
    }
}

// MARK: - Batch Job Tracker

/// Tracks batch jobs and their status
public class BatchJobTracker {
    public static let shared = BatchJobTracker()
    
    private var activeJobs: [String: JobStatusData] = [:]
    
    private init() {}
    
    public func registerJob(_ jobStatus: JobStatusData) {
        activeJobs[jobStatus.jobId] = jobStatus
    }
    
    public func updateJobStatus(_ jobStatus: JobStatusData) {
        activeJobs[jobStatus.jobId] = jobStatus
    }
    
    public func getJobStatus(jobId: String) -> JobStatusData? {
        return activeJobs[jobId]
    }
    
    public func getAllJobs() -> [JobStatusData] {
        return Array(activeJobs.values)
    }
    
    public func removeJob(jobId: String) {
        activeJobs.removeValue(forKey: jobId)
    }
}

// MARK: - JSON Helpers

extension Data {
    public func toJSONString() -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: self, options: []),
              let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
}

// MARK: - Global Signature Service

/// Service for accessing the global image signature database
public class GlobalSignatureService {
    
    // MARK: - Properties
    
    public static let shared = GlobalSignatureService()
    
    private let lambdaService: LambdaService
    
    // MARK: - Initialization
    
    private init() {
        self.lambdaService = LambdaService.shared
    }
    
    // MARK: - Public Methods
    
    /// Checks if a tag exists in the global signature database
    /// - Parameter tag: Tag to check
    /// - Returns: Whether the tag exists
    public func checkTagExists(_ tag: String) async throws -> Bool {
        let payload: [String: Any] = [
            "action": "checkTag",
            "tag": tag
        ]
        
        let data = try await lambdaService.invoke(
            functionName: "GlobalSignatureService",
            payload: payload
        )
        
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exists = jsonResponse["exists"] as? Bool else {
            throw LambdaService.LambdaServiceError.invalidResponse
        }
        
        return exists
    }
    
    /// Adds a tag to the global signature database
    /// - Parameter tag: Tag to add
    /// - Returns: Success flag
    public func addTag(_ tag: String) async throws -> Bool {
        let payload: [String: Any] = [
            "action": "addTag",
            "tag": tag
        ]
        
        let data = try await lambdaService.invoke(
            functionName: "GlobalSignatureService",
            payload: payload
        )
        
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool else {
            throw LambdaService.LambdaServiceError.invalidResponse
        }
        
        return success
    }
} 