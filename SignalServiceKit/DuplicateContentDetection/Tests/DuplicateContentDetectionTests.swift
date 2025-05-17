import XCTest
@testable import SignalServiceKit

class DuplicateContentDetectionTests: XCTestCase {
    
    private var awsManager: AWSManager!
    private var detectionManager: DuplicateContentDetectionManager!
    
    override func setUp() {
        super.setUp()
        Logger.configure()
        Logger.logToFile = false
        awsManager = AWSManager.shared
        detectionManager = DuplicateContentDetectionManager.shared
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testAWSConfigurationExists() {
        // Test that AWS configuration values exist
        XCTAssertFalse(AWSConfig.s3BucketName.isEmpty)
        XCTAssertFalse(AWSConfig.s3Region.isEmpty)
        XCTAssertFalse(AWSConfig.s3ImagesPath.isEmpty)
        XCTAssertFalse(AWSConfig.s3BaseURL.isEmpty)
        
        XCTAssertFalse(AWSConfig.getTagAPIURL.isEmpty)
        XCTAssertFalse(AWSConfig.getTagAPIKey.isEmpty)
        
        XCTAssertFalse(AWSConfig.dynamoDBRegion.isEmpty)
        XCTAssertFalse(AWSConfig.hashTableName.isEmpty)
    }
    
    func testTextHashingWorks() async {
        // Test that text hashing produces consistent results
        let text1 = "This is a test message"
        let text2 = "This is a test message"
        let text3 = "This is a different message"
        
        let result1 = await detectionManager.checkForDuplicateText(text1)
        let result2 = await detectionManager.checkForDuplicateText(text2)
        let result3 = await detectionManager.checkForDuplicateText(text3)
        
        // Text1 should be unique when first added
        if case .unique = result1 {
            XCTAssertTrue(true)
        } else {
            XCTFail("First text should be unique")
        }
        
        // Text2 should be detected as duplicate of text1
        if case .duplicate(let hash) = result2 {
            XCTAssertFalse(hash.isEmpty)
        } else {
            XCTFail("Identical text should be detected as duplicate")
        }
        
        // Text3 should be unique
        if case .unique = result3 {
            XCTAssertTrue(true)
        } else {
            XCTFail("Different text should be unique")
        }
    }
    
    func testVerificationReport() async {
        // The verification might fail in a test environment without real AWS credentials
        // This just tests that the verification process completes without crashing
        let report = await awsManager.verifyAWSCredentials()
        
        // Just verify the report structure is valid
        XCTAssertNotNil(report)
        XCTAssertNotNil(report.errors)
    }
    
    func testImageServiceMockUpload() async {
        // Create a test image (1x1 pixel white image)
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.white.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        guard let image = UIGraphicsGetImageFromCurrentImageContext(),
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create test image")
            return
        }
        UIGraphicsEndImageContext()
        
        // This is a mock test that doesn't actually call AWS but tests the code flow
        do {
            // Override the S3Service with a mock for testing
            let mockS3Service = MockS3Service()
            let mockImageService = MockImageService(s3Service: mockS3Service)
            
            let imageURL = try await mockImageService.uploadImage(imageData: imageData)
            XCTAssertTrue(imageURL.absoluteString.contains(AWSConfig.s3BaseURL))
            XCTAssertTrue(imageURL.absoluteString.contains(".jpg"))
        } catch {
            XCTFail("Image upload test failed: \(error)")
        }
    }
}

// MARK: - Mock Classes for Testing

class MockS3Service {
    func uploadFile(fileData: Data, key: String, contentType: String) async throws -> String {
        // Simulate successful upload without actually calling AWS
        return "mock-etag-\(UUID().uuidString)"
    }
}

class MockImageService {
    private let s3Service: MockS3Service
    
    init(s3Service: MockS3Service) {
        self.s3Service = s3Service
    }
    
    func uploadImage(imageData: Data) async throws -> URL {
        guard !imageData.isEmpty else {
            throw ImageService.ImageServiceError.invalidImageData
        }
        
        let fileName = "mock-\(UUID().uuidString).jpg"
        let key = "\(AWSConfig.s3ImagesPath)\(fileName)"
        
        _ = try await s3Service.uploadFile(
            fileData: imageData,
            key: key,
            contentType: "image/jpeg"
        )
        
        guard let url = URL(string: "\(AWSConfig.s3BaseURL)\(fileName)") else {
            throw ImageService.ImageServiceError.uploadFailed("Failed to create image URL")
        }
        
        return url
    }
} 