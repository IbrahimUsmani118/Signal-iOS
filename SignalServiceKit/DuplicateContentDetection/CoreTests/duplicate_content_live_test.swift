import XCTest
import Foundation
import CocoaLumberjack
@testable import SignalServiceKit

/// These tests are disabled by default because they require real AWS credentials.
/// They are meant to be run manually to test the live interactions with AWS services.
final class DuplicateContentLiveTests: XCTestCase {
    
    // MARK: - Test Constants
    
    private let testHashValue = "test_hash_123456789"
    private let totalTestHashes = 10
    private let failedTestHashes = 2
    private let successTestHashes = 8
    
    // MARK: - Dependencies
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    private var credentialsManager: AWSCredentialsVerificationManager!
    private var globalSignatureService: GlobalSignatureService!
    private var serviceMock: AWSServiceMock!
    private var testReport: AWSDependencyVerificationReport!
    
    // MARK: - Test Setup
    
    override func setUp() {
        super.setUp()
        
        // Skip these tests by default
        continueAfterFailure = false
        
        // Initialize dependencies
        serviceMock = AWSServiceMock()
        credentialsManager = AWSCredentialsVerificationManager.shared
        globalSignatureService = GlobalSignatureService()
        
        testReport = AWSDependencyVerificationReport(
            awsCredentialsValid: true,
            dynamoDBAccessible: true,
            s3Accessible: true,
            apiGatewayAccessible: true,
            details: "Test report"
        )
    }
    
    override func tearDown() {
        serviceMock.resetAllBehaviors()
        super.tearDown()
    }
    
    // MARK: - Test Utils
    
    func printDebug(_ message: String) {
        Logger.debug(message)
    }
    
    func logReport() {
        let report = testReport.full
        print(report)
    }
    
    // MARK: - Disabled AWS Tests
    
    func testSkipAWSTests() throws {
        XCTAssertTrue(true, "This is just a placeholder test")
    }
    
    // To run live AWS tests, comment out the above test and uncomment these tests
    
    /*
    func testAWSCredentialsVerification() async throws {
        let isValid = await credentialsManager.verifyCredentials()
        XCTAssertTrue(isValid, "AWS credentials should be valid")
    }
    
    func testGenerateDependencyReport() async throws {
        let report = await credentialsManager.generateVerificationReport()
        XCTAssertTrue(report.awsCredentialsValid, "AWS credentials should be valid")
        XCTAssertTrue(report.dynamoDBAccessible, "DynamoDB should be accessible")
        XCTAssertTrue(report.s3Accessible, "S3 should be accessible")
        XCTAssertTrue(report.apiGatewayAccessible, "API Gateway should be accessible")
        
        let fullReport = report.full
        print(fullReport)
    }
    
    func testCheckSignatureExistence() async throws {
        let exists = try await globalSignatureService.checkSignatureExists(testHashValue)
        XCTAssertFalse(exists, "Test hash should not exist initially")
    }
    
    func testStoreAndRetrieveSignature() async throws {
        // First ensure it doesn't exist
        let existsInitially = try await globalSignatureService.checkSignatureExists(testHashValue)
        XCTAssertFalse(existsInitially, "Test hash should not exist initially")
        
        // Store it
        try await globalSignatureService.storeSignature(testHashValue)
        
        // Check it exists now
        let existsAfterStore = try await globalSignatureService.checkSignatureExists(testHashValue)
        XCTAssertTrue(existsAfterStore, "Test hash should exist after storing")
        
        // Clean up - delete it
        try await globalSignatureService.deleteSignature(testHashValue)
        
        // Verify it's gone
        let existsAfterDelete = try await globalSignatureService.checkSignatureExists(testHashValue)
        XCTAssertFalse(existsAfterDelete, "Test hash should not exist after deletion")
    }
    */
    
    // MARK: - Mock-based Tests
    
    func testMockServiceResetsBehaviors() {
        serviceMock.simulateDynamoDBError(.accessDenied)
        XCTAssertNotEqual(serviceMock.dynamoDBBehavior, .success)
        
        serviceMock.resetAllBehaviors()
        XCTAssertEqual(serviceMock.dynamoDBBehavior, .success)
        XCTAssertEqual(serviceMock.s3Behavior, .success)
        XCTAssertEqual(serviceMock.apiGatewayBehavior, .success)
        XCTAssertEqual(serviceMock.cognitoBehavior, .success)
    }
    
    func testAWSCredentialsVerificationManagerGeneratesReport() async {
        let report = await AWSCredentialsVerificationManager.shared.generateVerificationReport()
        XCTAssertTrue(report.allDependenciesValid, "Default mock should report all dependencies as valid")
    }
    
    func testS3toDynamoDBImporterStateManagement() {
        let importer = S3toDynamoDBImporter.shared
        
        // Initial state should be notStarted
        if case .notStarted = importer.currentStatus.status {
            XCTAssertEqual(importer.currentStatus.progress, 0)
        } else {
            XCTFail("Initial state should be .notStarted")
        }
        
        // Start the import
        importer.beginImport()
        
        // After beginning import, it should be in progress
        if case .inProgress = importer.currentStatus.status {
            // Progress should be greater than 0 now
            XCTAssertGreaterThan(importer.currentStatus.progress, 0)
        } else {
            XCTFail("State should be .inProgress after beginImport()")
        }
        
        // Cancel the import
        importer.cancelImport()
        
        // Reset for the next test
        importer.resetStatus()
        
        // After reset, state should be back to notStarted
        if case .notStarted = importer.currentStatus.status {
            XCTAssertEqual(importer.currentStatus.progress, 0)
        } else {
            XCTFail("State should be .notStarted after resetStatus()")
        }
    }
    
    func testAsyncAwaitCompatibility() async {
        let allChunksSucceeded = { (task: Task<Bool, Never>) async -> Bool in
            return await task.value
        }
        
        let result = await allChunksSucceeded(Task { true })
        XCTAssertTrue(result)
    }
    
    func testLogLevels() {
        Logger.debug("Debug level message")
        Logger.info("Info level message")
        Logger.warn("Warning level message")
        Logger.error("Error level message")
        
        DDLog.flushLog()
    }
    
    // MARK: - Error Handling Tests
    
    func testAccessDeniedErrorHandling() {
        serviceMock.simulateDynamoDBError(.accessDenied)
        
        XCTAssertEqual(
            (serviceMock.dynamoDBBehavior, .fail(AWSDynamoDBErrorType.accessDenied) as AWSServiceMock.MockBehavior),
            "DynamoDB behavior should be to fail with access denied error"
        )
    }
    
    func testComplexErrorHandling() {
        // Breaking up the complex expression into simpler parts
        let error1: AWSDynamoDBErrorType = .accessDenied
        let error2: AWSDynamoDBErrorType = .conditionalCheckFailed
        
        XCTAssertNotEqual(error1, error2)
        XCTAssertFalse(error1.isTransient)
        XCTAssertFalse(error2.isTransient)
        
        // Test with transient errors
        let transientError1: AWSDynamoDBErrorType = .throttlingException
        let transientError2: AWSDynamoDBErrorType = .provisionedThroughputExceeded
        let transientError3: AWSDynamoDBErrorType = .internalServerError
        
        XCTAssertTrue(transientError1.isTransient)
        XCTAssertTrue(transientError2.isTransient)
        XCTAssertTrue(transientError3.isTransient)
    }
    
    func testCognitoErrorHandling() {
        // Breaking up the complex expression into simpler parts
        let error1: AWSCognitoIdentityErrorType = .tooManyRequestsException
        let error2: AWSCognitoIdentityErrorType = .internalErrorException
        
        XCTAssertTrue(error1.isTransient)
        XCTAssertTrue(error2.isTransient)
        
        // Test with non-transient errors
        let nonTransientError1: AWSCognitoIdentityErrorType = .notAuthorized
        let nonTransientError2: AWSCognitoIdentityErrorType = .invalidParameter
        
        XCTAssertFalse(nonTransientError1.isTransient)
        XCTAssertFalse(nonTransientError2.isTransient)
    }
} 