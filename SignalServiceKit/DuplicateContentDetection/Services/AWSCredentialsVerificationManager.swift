import Foundation
import CocoaLumberjack

/// Report on AWS dependencies verification
public struct AWSDependencyVerificationReport {
    public let awsCredentialsValid: Bool
    public let s3Accessible: Bool
    public let dynamoDBAccessible: Bool
    public let apiGatewayAccessible: Bool
    public let errors: [String]
    
    /// Creates a verification report with default values (all false)
    public static func createDefault() -> AWSDependencyVerificationReport {
        return AWSDependencyVerificationReport(
            awsCredentialsValid: false,
            s3Accessible: false,
            dynamoDBAccessible: false,
            apiGatewayAccessible: false,
            errors: []
        )
    }
}

/// Manager for verifying AWS credentials and services
public class AWSCredentialsVerificationManager {
    
    // MARK: - Properties
    
    public static let shared = AWSCredentialsVerificationManager()
    
    private let session: URLSession
    private var errors: [String] = []
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AWSConfig.requestTimeoutSeconds
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Generates a verification report for AWS dependencies
    /// - Returns: Verification report
    public func generateVerificationReport() async -> AWSDependencyVerificationReport {
        errors.removeAll()
        
        // Check AWS credentials
        let credentialsValid = await verifyAWSCredentials()
        
        // Check S3 access
        let s3Accessible = await verifyS3Access()
        
        // Check DynamoDB access
        let dynamoDBAccessible = await verifyDynamoDBAccess()
        
        // Check API Gateway access
        let apiGatewayAccessible = await verifyAPIGatewayAccess()
        
        return AWSDependencyVerificationReport(
            awsCredentialsValid: credentialsValid,
            s3Accessible: s3Accessible,
            dynamoDBAccessible: dynamoDBAccessible,
            apiGatewayAccessible: apiGatewayAccessible,
            errors: errors
        )
    }
    
    // MARK: - Private Methods
    
    /// Verifies AWS credentials
    /// - Returns: Whether the credentials are valid
    private func verifyAWSCredentials() async -> Bool {
        guard !AWSConfig.accessKeyId.isEmpty && !AWSConfig.secretAccessKey.isEmpty else {
            errors.append("AWS credentials not provided")
            return false
        }
        
        // In a real implementation, you would verify the credentials with AWS STS
        // Here we're just checking if they exist and aren't empty
        
        return true
    }
    
    /// Verifies S3 access
    /// - Returns: Whether S3 is accessible
    private func verifyS3Access() async -> Bool {
        do {
            // Try to upload a small test file to S3
            let testData = "test".data(using: .utf8)!
            let testKey = "test/verification-\(UUID().uuidString).txt"
            
            _ = try await S3Service.shared.uploadFile(
                fileData: testData,
                key: testKey,
                contentType: "text/plain"
            )
            
            return true
        } catch {
            errors.append("S3 access failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Verifies DynamoDB access
    /// - Returns: Whether DynamoDB is accessible
    private func verifyDynamoDBAccess() async -> Bool {
        // Build a simple ping request to the DynamoDB endpoint
        let pingURL = "\(AWSConfig.dynamoDBEndpoint)/ping"
        
        guard let url = URL(string: pingURL) else {
            errors.append("Invalid DynamoDB endpoint URL")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errors.append("Invalid response type from DynamoDB endpoint")
                return false
            }
            
            let isSuccess = httpResponse.statusCode >= 200 && httpResponse.statusCode < 300
            
            if !isSuccess {
                errors.append("DynamoDB access failed with status code: \(httpResponse.statusCode)")
            }
            
            return isSuccess
        } catch {
            errors.append("DynamoDB access failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Verifies API Gateway access
    /// - Returns: Whether API Gateway is accessible
    private func verifyAPIGatewayAccess() async -> Bool {
        // Build a simple ping request to the API Gateway endpoint
        let pingURL = "\(AWSConfig.apiGatewayEndpoint)/ping"
        
        guard let url = URL(string: pingURL) else {
            errors.append("Invalid API Gateway endpoint URL")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if !AWSConfig.apiKey.isEmpty {
            request.setValue(AWSConfig.apiKey, forHTTPHeaderField: "x-api-key")
        }
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errors.append("Invalid response type from API Gateway endpoint")
                return false
            }
            
            let isSuccess = httpResponse.statusCode >= 200 && httpResponse.statusCode < 300
            
            if !isSuccess {
                errors.append("API Gateway access failed with status code: \(httpResponse.statusCode)")
            }
            
            return isSuccess
        } catch {
            errors.append("API Gateway access failed: \(error.localizedDescription)")
            return false
        }
    }
} 