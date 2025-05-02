import XCTest
import AWSCore
import AWSS3
import AWSDynamoDB
import SignalCoreKit
import Logging

class AWSUploadServiceTests: XCTestCase {
    private var uploadService: AWSUploadService!
    private var mockS3Client: MockS3Client!
    private var mockDynamoDBClient: MockDynamoDBClient!
    private let logger = Logger(label: "org.signal.tests.AWSUploadServiceTests")
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup mock clients
        mockS3Client = MockS3Client()
        mockDynamoDBClient = MockDynamoDBClient()
        
        // Initialize service with mock clients
        uploadService = try AWSUploadService()
        uploadService.s3Client = mockS3Client
        uploadService.dynamoDBClient = mockDynamoDBClient
    }
    
    override func tearDown() async throws {
        mockS3Client = nil
        mockDynamoDBClient = nil
        uploadService = nil
        try await super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testUploadSmallFile() async throws {
        // Create test file
        let testFile = try createTestFile(size: 1024) // 1KB file
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        // Upload file
        let s3Key = try await uploadService.uploadFile(
            testFile,
            contentType: "application/octet-stream",
            metadata: ["test": "value"]
        )
        
        // Verify S3 upload
        XCTAssertTrue(mockS3Client.didUploadFile)
        XCTAssertEqual(mockS3Client.lastUploadKey, s3Key)
        XCTAssertEqual(mockS3Client.lastUploadBucket, AWSConfig.s3Bucket)
        
        // Verify DynamoDB metadata
        XCTAssertTrue(mockDynamoDBClient.didStoreMetadata)
        XCTAssertEqual(mockDynamoDBClient.lastStoredKey, s3Key)
    }
    
    func testUploadLargeFile() async throws {
        // Create test file
        let testFile = try createTestFile(size: 10 * 1024 * 1024) // 10MB file
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        // Upload file
        let s3Key = try await uploadService.uploadFile(
            testFile,
            contentType: "application/octet-stream",
            metadata: ["test": "value"]
        )
        
        // Verify multipart upload
        XCTAssertTrue(mockS3Client.didInitiateMultipartUpload)
        XCTAssertTrue(mockS3Client.didUploadParts)
        XCTAssertTrue(mockS3Client.didCompleteMultipartUpload)
        XCTAssertEqual(mockS3Client.lastUploadKey, s3Key)
        
        // Verify DynamoDB metadata
        XCTAssertTrue(mockDynamoDBClient.didStoreMetadata)
        XCTAssertEqual(mockDynamoDBClient.lastStoredKey, s3Key)
    }
    
    func testDuplicateDetection() async throws {
        // Create test file
        let testFile = try createTestFile(size: 1024)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        // Setup mock to indicate file exists
        mockDynamoDBClient.shouldFindDuplicate = true
        
        // Upload file
        let s3Key = try await uploadService.uploadFile(
            testFile,
            contentType: "application/octet-stream"
        )
        
        // Verify no S3 upload occurred
        XCTAssertFalse(mockS3Client.didUploadFile)
        XCTAssertFalse(mockS3Client.didInitiateMultipartUpload)
        
        // Verify no new metadata was stored
        XCTAssertFalse(mockDynamoDBClient.didStoreMetadata)
    }
    
    func testErrorHandling() async throws {
        // Create test file
        let testFile = try createTestFile(size: 1024)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        // Setup mock to throw error
        mockS3Client.shouldThrowError = true
        
        // Attempt upload
        do {
            _ = try await uploadService.uploadFile(
                testFile,
                contentType: "application/octet-stream"
            )
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is AWSUploadError)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestFile(size: Int) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test_file_\(UUID().uuidString).dat"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        // Create file with random data
        let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
        try data.write(to: fileURL)
        
        return fileURL
    }
}

// MARK: - Mock Clients

class MockS3Client: AWSS3 {
    var didUploadFile = false
    var didInitiateMultipartUpload = false
    var didUploadParts = false
    var didCompleteMultipartUpload = false
    var lastUploadKey: String?
    var lastUploadBucket: String?
    var shouldThrowError = false
    
    override func putObject(_ request: AWSS3PutObjectRequest) async throws -> AWSS3PutObjectOutput {
        if shouldThrowError {
            throw NSError(domain: "MockS3Client", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        
        didUploadFile = true
        lastUploadKey = request.key
        lastUploadBucket = request.bucket
        return AWSS3PutObjectOutput()
    }
    
    override func createMultipartUpload(_ request: AWSS3CreateMultipartUploadRequest) async throws -> AWSS3CreateMultipartUploadOutput {
        if shouldThrowError {
            throw NSError(domain: "MockS3Client", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        
        didInitiateMultipartUpload = true
        lastUploadKey = request.key
        lastUploadBucket = request.bucket
        
        let output = AWSS3CreateMultipartUploadOutput()
        output.uploadId = "mock-upload-id"
        return output
    }
    
    override func uploadPart(_ request: AWSS3UploadPartRequest) async throws -> AWSS3UploadPartOutput {
        if shouldThrowError {
            throw NSError(domain: "MockS3Client", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        
        didUploadParts = true
        let output = AWSS3UploadPartOutput()
        output.eTag = "mock-etag"
        return output
    }
    
    override func completeMultipartUpload(_ request: AWSS3CompleteMultipartUploadRequest) async throws -> AWSS3CompleteMultipartUploadOutput {
        if shouldThrowError {
            throw NSError(domain: "MockS3Client", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        
        didCompleteMultipartUpload = true
        return AWSS3CompleteMultipartUploadOutput()
    }
}

class MockDynamoDBClient: AWSDynamoDB {
    var didStoreMetadata = false
    var lastStoredKey: String?
    var shouldFindDuplicate = false
    var shouldThrowError = false
    
    override func query(_ request: AWSDynamoDBQueryInput) async throws -> AWSDynamoDBQueryOutput {
        if shouldThrowError {
            throw NSError(domain: "MockDynamoDBClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        
        let output = AWSDynamoDBQueryOutput()
        if shouldFindDuplicate {
            let item = AWSDynamoDBAttributeValue()
            item.s = "mock-s3-key"
            output.items = [["s3_key": item]]
        } else {
            output.items = []
        }
        return output
    }
    
    override func putItem(_ request: AWSDynamoDBPutItemInput) async throws -> AWSDynamoDBPutItemOutput {
        if shouldThrowError {
            throw NSError(domain: "MockDynamoDBClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
        
        didStoreMetadata = true
        lastStoredKey = request.item?["s3_key"]?.s
        return AWSDynamoDBPutItemOutput()
    }
} 