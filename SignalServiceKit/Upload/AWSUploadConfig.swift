import Foundation
import AWSCore
import AWSCognitoIdentity
import SignalCoreKit

/// Centralized AWS configuration management for file uploads
class AWSUploadConfig {
    // MARK: - Constants
    
    /// AWS region for all services
    static let region = AWSRegionType.USEast1
    
    /// Cognito Identity Pool ID
    static let identityPoolId = "us-east-1:a41de7b5-bc6b-48f7-ba53-2c45d0466c4c"
    
    /// S3 bucket name
    static let s3Bucket = "2314823894myawsbucket"
    
    /// S3 prefix for uploaded files
    static let s3Prefix = "images/"
    
    /// DynamoDB table name
    static let dynamoDBTable = "SignalMetadata"
    
    /// Request timeout interval in seconds
    static let requestTimeoutInterval: TimeInterval = 30.0
    
    /// Resource timeout interval in seconds
    static let resourceTimeoutInterval: TimeInterval = 300.0
    
    /// Maximum number of retry attempts
    static let maxRetryCount = 3
    
    // MARK: - Configuration
    
    /// Sets up AWS credentials and configuration
    static func setupAWSCredentials() {
        // Configure Cognito credentials provider
        let credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: region,
            identityPoolId: identityPoolId
        )
        
        // Create service configuration
        let configuration = AWSServiceConfiguration(
            region: region,
            credentialsProvider: credentialsProvider
        )
        
        // Set as default configuration
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        // Configure logging
        AWSDDLog.sharedInstance.logLevel = .verbose
    }
    
    /// Validates AWS configuration
    static func validateConfiguration() throws {
        guard !identityPoolId.isEmpty else {
            throw OWSAssertionError("AWS Identity Pool ID is not configured")
        }
        
        guard !s3Bucket.isEmpty else {
            throw OWSAssertionError("S3 bucket name is not configured")
        }
        
        guard !dynamoDBTable.isEmpty else {
            throw OWSAssertionError("DynamoDB table name is not configured")
        }
    }
} 