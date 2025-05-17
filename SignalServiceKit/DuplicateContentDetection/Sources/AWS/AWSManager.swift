import Foundation
import SignalServiceKit
import CocoaLumberjack

// MARK: - AWSManager

/// Main manager class for AWS-related functionality
public class AWSManager {
    
    // MARK: - Properties
    
    public static let shared = AWSManager()
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // MARK: - Service Accessors
    
    /// Access to the S3 service
    public var s3Service: S3Service {
        return S3Service.shared
    }
    
    /// Access to the Lambda service
    public var lambdaService: LambdaService {
        return LambdaService.shared
    }
    
    /// Access to the API Gateway client
    public var apiGatewayClient: APIGatewayClient {
        return APIGatewayClient.shared
    }
    
    /// Access to the Global Signature Service
    public var signatureService: GlobalSignatureService {
        return GlobalSignatureService.shared
    }
    
    // MARK: - Initialization
    
    private init() {
        Logger.debug("Initializing AWSManager")
    }
    
    // MARK: - Status Checking
    
    /// Checks if AWS credentials are valid and services are accessible
    /// - Returns: Verification report
    public func verifyAWSCredentials() async -> AWSDependencyVerificationReport {
        return await AWSCredentialsVerificationManager.shared.generateVerificationReport()
    }
    
    /// Checks if specific AWS services are available
    /// - Returns: Dictionary mapping service names to availability status
    public func checkServiceAvailability() async -> [String: Bool] {
        let report = await verifyAWSCredentials()
        
        return [
            "S3": report.s3Accessible,
            "DynamoDB": report.dynamoDBAccessible,
            "API Gateway": report.apiGatewayAccessible,
            "Credentials": report.awsCredentialsValid
        ]
    }
} 