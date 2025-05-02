//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Foundation
import SignalServiceKit
import AWSCore
import AWSDynamoDB
@testable import Signal

/// Live integration test for duplicate content detection system.
/// This test requires AWS credentials to be properly configured.
class DuplicateContentLiveTest: XCTestCase {
    
    // MARK: - Properties
    
    private var signatureService: GlobalSignatureService!
    private var downloadHook: AttachmentDownloadHook!
    private var messageSender: MessageSender!
    private var duplicateStore: DuplicateSignatureStore!
    
    // Test data
    private let testImageData = Data(repeating: 0xFF, count: 1024) // 1KB of test image data
    private let testTextData = "Test message content".data(using: .utf8)!
    
    // MARK: - Test Lifecycle
    
    override func setUp() async throws {
        super.setUp()
        TestMetrics.reset()
        
        // Initialize AWS services
        try initializeAWSServices()
        
        // Create services
        signatureService = GlobalSignatureService()
        duplicateStore = DuplicateSignatureStore()
        downloadHook = AttachmentDownloadHook(
            signatureService: signatureService,
            duplicateStore: duplicateStore
        )
        messageSender = MessageSender(
            signatureService: signatureService,
            duplicateStore: duplicateStore
        )
    }
    
    override func tearDown() async throws {
        // Clean up test data
        try await cleanupTestData()
        
        signatureService = nil
        downloadHook = nil
        messageSender = nil
        duplicateStore = nil
        
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testEndToEndFlow() async throws {
        // 1. Send an initial message with attachment
        let message1 = createTestMessage(withData: testImageData, type: "image/jpeg")
        let result1 = try await messageSender.sendMessage(message1)
        XCTAssertTrue(result1.success, "First message should send successfully")
        
        // Wait for hash to be stored
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // 2. Try to send the same content again
        let message2 = createTestMessage(withData: testImageData, type: "image/jpeg")
        let result2 = try await messageSender.sendMessage(message2)
        XCTAssertFalse(result2.success, "Duplicate message should be blocked")
        
        if case .duplicateBlocked(let hash) = result2.error as? MessageSenderError {
            XCTAssertNotNil(hash, "Should have hash information for blocked content")
        } else {
            XCTFail("Expected duplicate blocked error")
        }
        
        // 3. Try to download the blocked content
        let attachment = createTestAttachment(withData: testImageData, type: "image/jpeg")
        let downloadResult = try await downloadHook.processDownloadedAttachment(attachment)
        XCTAssertFalse(downloadResult.allowDownload, "Download of blocked content should be prevented")
        XCTAssertEqual(downloadResult.blockReason, .globallyBlocked)
        
        // 4. Verify different content is still allowed
        let differentMessage = createTestMessage(withData: testTextData, type: "text/plain")
        let result3 = try await messageSender.sendMessage(differentMessage)
        XCTAssertTrue(result3.success, "Different content should be allowed")
    }
    
    func testLocalBlockingFlow() async throws {
        // 1. Create test content and compute its hash
        let testData = "locally blocked content".data(using: .utf8)!
        let hash = try calculateContentHash(testData)
        
        // 2. Add hash to local blocklist
        try await duplicateStore.blockHash(hash)
        
        // 3. Try to send message with blocked content
        let message = createTestMessage(withData: testData, type: "text/plain")
        let result = try await messageSender.sendMessage(message)
        XCTAssertFalse(result.success, "Message with locally blocked content should be blocked")
        
        // 4. Verify download is also blocked
        let attachment = createTestAttachment(withData: testData, type: "text/plain")
        let downloadResult = try await downloadHook.processDownloadedAttachment(attachment)
        XCTAssertFalse(downloadResult.allowDownload, "Download of locally blocked content should be prevented")
        XCTAssertEqual(downloadResult.blockReason, .locallyBlocked)
    }
    
    func testPerformanceWithLargeContent() async throws {
        // Create 5MB of test data
        let largeData = Data(repeating: 0x41, count: 5 * 1024 * 1024)
        
        // Measure send performance
        measure {
            let message = createTestMessage(withData: largeData, type: "application/octet-stream")
            let expectation = XCTestExpectation(description: "Message send complete")
            
            Task {
                let result = try await messageSender.sendMessage(message)
                XCTAssertTrue(result.success, "Large content send should succeed")
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    // MARK: - Additional Test Cases
    
    func testConcurrentUploads() async throws {
        let concurrentCount = 10
        let expectation = XCTestExpectation(description: "Concurrent uploads complete")
        expectation.expectedFulfillmentCount = concurrentCount
        
        // Create unique test data for each upload
        let uploads = (0..<concurrentCount).map { index in
            Task {
                let uniqueData = "concurrent test \(index)".data(using: .utf8)!
                let message = createTestMessage(withData: uniqueData, type: "text/plain")
                let result = try await messageSender.sendMessage(message)
                XCTAssertTrue(result.success, "Upload \(index) should succeed")
                expectation.fulfill()
            }
        }
        
        // Wait for all uploads with timeout
        await fulfillment(of: [expectation], timeout: 30.0)
        
        // Verify all tasks completed
        for (index, upload) in uploads.enumerated() {
            do {
                try await upload.value
            } catch {
                XCTFail("Upload \(index) failed with error: \(error)")
            }
        }
    }
    
    func testLargeFileHandling() async throws {
        // Test with files of increasing sizes
        let sizes = [1, 5, 10, 20] // MB
        
        for size in sizes {
            let data = Data(repeating: 0x41, count: size * 1024 * 1024)
            let message = createTestMessage(withData: data, type: "application/octet-stream")
            
            let start = Date()
            let result = try await messageSender.sendMessage(message)
            let duration = Date().timeIntervalSince(start)
            
            XCTAssertTrue(result.success, "Upload of \(size)MB file should succeed")
            print("Time to process \(size)MB: \(duration) seconds")
            
            // Performance assertion - adjust threshold based on requirements
            XCTAssertLessThan(duration, Double(size) * 2.0, "Processing \(size)MB should take less than \(size * 2) seconds")
        }
    }
    
    func testEdgeCases() async throws {
        // Test empty content
        let emptyMessage = createTestMessage(withData: Data(), type: "text/plain")
        let emptyResult = try await messageSender.sendMessage(emptyMessage)
        XCTAssertFalse(emptyResult.success, "Empty content should be rejected")
        
        // Test very small content (1 byte)
        let tinyData = Data([0x41])
        let tinyMessage = createTestMessage(withData: tinyData, type: "text/plain")
        let tinyResult = try await messageSender.sendMessage(tinyMessage)
        XCTAssertTrue(tinyResult.success, "Small content should be accepted")
        
        // Test invalid content type
        let invalidMessage = createTestMessage(withData: testImageData, type: "invalid/type")
        let invalidResult = try await messageSender.sendMessage(invalidMessage)
        XCTAssertFalse(invalidResult.success, "Invalid content type should be rejected")
    }
    
    func testRetryBehavior() async throws {
        // Simulate network failures and verify retry behavior
        let retryCount = 3
        var attemptCount = 0
        
        let message = createTestMessage(withData: testImageData, type: "image/jpeg")
        
        // Override messageSender to simulate failures
        class RetryMessageSender: MessageSender {
            var attemptCount = 0
            let failureCount: Int
            
            init(signatureService: GlobalSignatureService, duplicateStore: DuplicateSignatureStore, failureCount: Int) {
                self.failureCount = failureCount
                super.init(signatureService: signatureService, duplicateStore: duplicateStore)
            }
            
            override func sendMessage(_ message: Message) async throws -> SendResult {
                attemptCount += 1
                if attemptCount <= failureCount {
                    return SendResult(success: false, error: MessageSenderError.networkError)
                }
                return try await super.sendMessage(message)
            }
        }
        
        let retrySender = RetryMessageSender(
            signatureService: signatureService,
            duplicateStore: duplicateStore,
            failureCount: retryCount - 1
        )
        
        let result = try await retrySender.sendMessage(message)
        XCTAssertTrue(result.success, "Message should eventually succeed after retries")
        XCTAssertEqual(retrySender.attemptCount, retryCount, "Should have attempted exactly \(retryCount) times")
    }
    
    // MARK: - Helper Methods
    
    private func initializeAWSServices() throws {
        let credentialsProvider = AWSStaticCredentialsProvider(
            accessKey: ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] ?? "",
            secretKey: ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] ?? ""
        )
        
        let configuration = AWSServiceConfiguration(
            region: .USEast1,
            credentialsProvider: credentialsProvider
        )
        
        AWSServiceManager.default().defaultServiceConfiguration = configuration
    }
    
    private func cleanupTestData() async throws {
        // Clean up any test data created during the test
        // This would typically involve removing test entries from DynamoDB
        // and clearing any local storage
    }
    
    private func createTestMessage(withData data: Data, type: String) -> Message {
        let message = Message(uniqueId: UUID().uuidString)
        let attachment = createTestAttachment(withData: data, type: type)
        message.attachments = [attachment]
        return message
    }
    
    private func createTestAttachment(withData data: Data, type: String) -> Attachment {
        let attachment = Attachment(uniqueId: UUID().uuidString, contentType: type)
        attachment.data = data
        return attachment
    }
    
    private func calculateContentHash(_ data: Data) throws -> String {
        let sha256 = data.withUnsafeBytes { bytes in
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return sha256.map { String(format: "%02x", $0) }.joined()
    }
    
    private func generateRandomData(size: Int) -> Data {
        var data = Data(count: size)
        _ = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, size, bytes.baseAddress!)
        }
        return data
    }
}

// MARK: - Test Support Classes

class Message {
    let uniqueId: String
    var attachments: [Attachment]?
    
    init(uniqueId: String) {
        self.uniqueId = uniqueId
    }
}

class Attachment {
    let uniqueId: String
    let contentType: String
    var data: Data?
    
    init(uniqueId: String, contentType: String) {
        self.uniqueId = uniqueId
        self.contentType = contentType
    }
}

class MessageSender {
    private let signatureService: GlobalSignatureService
    private let duplicateStore: DuplicateSignatureStore
    
    init(signatureService: GlobalSignatureService, duplicateStore: DuplicateSignatureStore) {
        self.signatureService = signatureService
        self.duplicateStore = duplicateStore
    }
    
    func sendMessage(_ message: Message) async throws -> SendResult {
        // Check attachments for duplicates
        if let attachment = message.attachments?.first,
           let data = attachment.data {
            let hash = try calculateContentHash(data)
            
            // Check local blocklist first
            if try await duplicateStore.isBlocked(hash) {
                return SendResult(success: false, error: MessageSenderError.duplicateBlocked(hash: hash))
            }
            
            // Then check global database
            if try await signatureService.contains(hash) {
                return SendResult(success: false, error: MessageSenderError.duplicateBlocked(hash: hash))
            }
            
            // Store hash after successful send
            try await signatureService.store(hash)
        }
        
        return SendResult(success: true, error: nil)
    }
    
    private func calculateContentHash(_ data: Data) throws -> String {
        let sha256 = data.withUnsafeBytes { bytes in
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return sha256.map { String(format: "%02x", $0) }.joined()
    }
}

struct SendResult {
    let success: Bool
    let error: Error?
}

enum MessageSenderError: Error {
    case duplicateBlocked(hash: String)
    case networkError
    
    var localizedDescription: String {
        switch self {
        case .duplicateBlocked:
            return "Message blocked due to duplicate content"
        case .networkError:
            return "Network error occurred while sending message"
        }
    }
}