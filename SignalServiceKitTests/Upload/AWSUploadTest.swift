import XCTest
import SignalServiceKit
import AWSS3
import AWSDynamoDB

class AWSUploadTest: XCTestCase {
    private var awsUpload: AWSUpload!
    private var testFileURL: URL!
    private var largeTestFileURL: URL!
    private var testFileHash: String!
    private let testDeviceId = "test-device-1"
    private let otherDeviceId = "test-device-2"
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create small test file
        let testData = "Test data for AWS upload".data(using: .utf8)!
        testFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_file.txt")
        try testData.write(to: testFileURL)
        
        // Create large test file (6MB)
        let largeTestData = Data(repeating: 0, count: 6 * 1024 * 1024)
        largeTestFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("large_test_file.dat")
        try largeTestData.write(to: largeTestFileURL)
        
        // Initialize AWS upload
        awsUpload = try AWSUpload()
        
        // Create test file
        testFileHash = SHA256.hash(data: testData).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testFileURL)
        try? FileManager.default.removeItem(at: largeTestFileURL)
        try await super.tearDown()
    }
    
    func testSmallFileUpload() async throws {
        // Create test metadata
        let metadata = try Upload.LocalUploadMetadata(
            fileUrl: testFileURL,
            key: Data(),
            digest: Data(),
            encryptedDataLength: UInt32(testFileURL.fileSize),
            plaintextDataLength: UInt32(testFileURL.fileSize)
        )
        
        // Create upload attempt
        let attempt = Upload.Attempt(
            cdnKey: "test_key",
            cdnNumber: 0,
            fileUrl: testFileURL,
            encryptedDataLength: UInt32(testFileURL.fileSize),
            localMetadata: metadata,
            beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            endpoint: .s3,
            uploadLocation: URL(string: "https://example.com")!,
            isResumedUpload: false,
            logger: PrefixedLogger(prefix: "Test")
        )
        
        // Perform upload
        var progressUpdates: [Progress] = []
        let result = try await awsUpload.upload(attempt) { progress in
            progressUpdates.append(progress)
        }
        
        // Verify results
        XCTAssertFalse(result.cdnKey.isEmpty)
        XCTAssertEqual(result.cdnNumber, 0)
        XCTAssertEqual(result.localUploadMetadata, metadata)
        XCTAssertGreaterThan(result.finishTimestamp, result.beginTimestamp)
        
        // Verify progress updates
        XCTAssertFalse(progressUpdates.isEmpty)
        XCTAssertEqual(progressUpdates.last?.completedUnitCount, 100)
    }
    
    func testLargeFileUpload() async throws {
        // Create test metadata
        let metadata = try Upload.LocalUploadMetadata(
            fileUrl: largeTestFileURL,
            key: Data(),
            digest: Data(),
            encryptedDataLength: UInt32(largeTestFileURL.fileSize),
            plaintextDataLength: UInt32(largeTestFileURL.fileSize)
        )
        
        // Create upload attempt
        let attempt = Upload.Attempt(
            cdnKey: "test_key",
            cdnNumber: 0,
            fileUrl: largeTestFileURL,
            encryptedDataLength: UInt32(largeTestFileURL.fileSize),
            localMetadata: metadata,
            beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            endpoint: .s3,
            uploadLocation: URL(string: "https://example.com")!,
            isResumedUpload: false,
            logger: PrefixedLogger(prefix: "Test")
        )
        
        // Perform upload
        var progressUpdates: [Progress] = []
        let result = try await awsUpload.upload(attempt) { progress in
            progressUpdates.append(progress)
        }
        
        // Verify results
        XCTAssertFalse(result.cdnKey.isEmpty)
        XCTAssertEqual(result.cdnNumber, 0)
        XCTAssertEqual(result.localUploadMetadata, metadata)
        XCTAssertGreaterThan(result.finishTimestamp, result.beginTimestamp)
        
        // Verify progress updates
        XCTAssertFalse(progressUpdates.isEmpty)
        XCTAssertEqual(progressUpdates.last?.completedUnitCount, 100)
        
        // Verify progress updates show incremental progress
        let progressValues = progressUpdates.map { $0.fractionCompleted }
        XCTAssertTrue(progressValues.isSorted())
    }
    
    func testUploadWithInvalidFile() async throws {
        // Create test metadata with invalid file
        let invalidURL = URL(fileURLWithPath: "/invalid/path")
        let metadata = try Upload.LocalUploadMetadata(
            fileUrl: invalidURL,
            key: Data(),
            digest: Data(),
            encryptedDataLength: 0,
            plaintextDataLength: 0
        )
        
        // Create upload attempt
        let attempt = Upload.Attempt(
            cdnKey: "test_key",
            cdnNumber: 0,
            fileUrl: invalidURL,
            encryptedDataLength: 0,
            localMetadata: metadata,
            beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            endpoint: .s3,
            uploadLocation: URL(string: "https://example.com")!,
            isResumedUpload: false,
            logger: PrefixedLogger(prefix: "Test")
        )
        
        // Attempt upload and expect failure
        do {
            _ = try await awsUpload.upload(attempt) { _ in }
            XCTFail("Expected upload to fail with invalid file")
        } catch {
            // Expected error
        }
    }
    
    func testUploadWithMissingConfiguration() async throws {
        // Temporarily remove AWS configuration
        let originalAccessKey = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"]
        defer {
            if let originalAccessKey = originalAccessKey {
                setenv("AWS_ACCESS_KEY_ID", originalAccessKey, 1)
            }
        }
        unsetenv("AWS_ACCESS_KEY_ID")
        
        // Attempt to create AWS upload and expect failure
        do {
            _ = try AWSUpload()
            XCTFail("Expected initialization to fail with missing configuration")
        } catch {
            // Expected error
        }
    }
    
    func testUploadFromDifferentDevices() async throws {
        // First upload from device 1
        let upload1 = try AWSUpload(deviceId: testDeviceId)
        let result1 = try await upload1.upload(
            Upload.Attempt(
                fileUrl: testFileURL,
                encryptedDataLength: 1024,
                localMetadata: Upload.LocalUploadMetadata(),
                beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            ),
            progress: { _ in }
        )
        
        // Second upload from device 2 should return the same S3 key
        let upload2 = try AWSUpload(deviceId: otherDeviceId)
        let result2 = try await upload2.upload(
            Upload.Attempt(
                fileUrl: testFileURL,
                encryptedDataLength: 1024,
                localMetadata: Upload.LocalUploadMetadata(),
                beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            ),
            progress: { _ in }
        )
        
        // Verify both uploads returned the same S3 key
        XCTAssertEqual(result1.cdnKey, result2.cdnKey)
        
        // Verify both device IDs are recorded in DynamoDB
        let dynamoDB = AWSDynamoDB.default()
        let queryInput = AWSDynamoDBQueryInput()
        queryInput.tableName = "SignalMetadata"
        queryInput.keyConditionExpression = "file_hash = :hash"
        queryInput.expressionAttributeValues = [":hash": AWSDynamoDBAttributeValue(string: testFileHash)]
        
        let queryOutput = try await dynamoDB.query(queryInput)
        XCTAssertNotNil(queryOutput.items)
        XCTAssertEqual(queryOutput.items?.count, 1)
        
        let item = queryOutput.items?.first
        let deviceIds = item?["device_ids"]?.ss ?? []
        XCTAssertTrue(deviceIds.contains(testDeviceId))
        XCTAssertTrue(deviceIds.contains(otherDeviceId))
    }
    
    func testDuplicateDetection() async throws {
        // First upload
        let upload1 = try AWSUpload(deviceId: testDeviceId)
        let result1 = try await upload1.upload(
            Upload.Attempt(
                fileUrl: testFileURL,
                encryptedDataLength: 1024,
                localMetadata: Upload.LocalUploadMetadata(),
                beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            ),
            progress: { _ in }
        )
        
        // Create a copy of the test file
        let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_file_copy.dat")
        try? FileManager.default.copyItem(at: testFileURL, to: copyURL)
        
        // Second upload of the same file
        let upload2 = try AWSUpload(deviceId: otherDeviceId)
        let result2 = try await upload2.upload(
            Upload.Attempt(
                fileUrl: copyURL,
                encryptedDataLength: 1024,
                localMetadata: Upload.LocalUploadMetadata(),
                beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            ),
            progress: { _ in }
        )
        
        // Clean up copy
        try? FileManager.default.removeItem(at: copyURL)
        
        // Verify both uploads returned the same S3 key
        XCTAssertEqual(result1.cdnKey, result2.cdnKey)
    }
    
    func testInvalidDeviceId() async throws {
        let upload = try AWSUpload(deviceId: "")
        do {
            _ = try await upload.upload(
                Upload.Attempt(
                    fileUrl: testFileURL,
                    encryptedDataLength: 1024,
                    localMetadata: Upload.LocalUploadMetadata(),
                    beginTimestamp: UInt64(Date().timeIntervalSince1970 * 1000)
                ),
                progress: { _ in }
            )
            XCTFail("Expected error for empty device ID")
        } catch {
            // Expected error
        }
    }
}

private extension URL {
    var fileSize: Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int ?? 0
    }
}

private extension Array where Element == Double {
    func isSorted() -> Bool {
        for i in 1..<count {
            if self[i] < this[i-1] {
                return false
            }
        }
        return true
    }
}

extension AWSDynamoDB {
    func query(_ input: AWSDynamoDBQueryInput) async throws -> AWSDynamoDBQueryOutput {
        try await withCheckedThrowingContinuation { continuation in
            self.query(input) { output, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let output = output {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(domain: "AWSUploadTest", code: -1, userInfo: nil))
                }
            }
        }
    }
} 