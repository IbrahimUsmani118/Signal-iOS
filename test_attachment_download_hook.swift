//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Foundation
import GRDB
import CryptoKit
import SignalServiceKit
@testable import Signal

/// This test validates the functionality of the AttachmentDownloadHook
/// which is responsible for preventing downloads of blocked content.
class AttachmentDownloadHookTests: XCTestCase {
    
    // MARK: - Properties
    
    private var mockSignatureService: MockGlobalSignatureService!
    private var mockDuplicateStore: MockDuplicateSignatureStore!
    private var downloadHook: AttachmentDownloadHook!
    private var reportedBlockedAttachments: [(hash: String, attachmentId: String?)] = []
    
    // MARK: - Test Lifecycle
    
    override func setUp() async throws {
        super.setUp()
        
        // Create mock services and database pool
        mockSignatureService = MockGlobalSignatureService()
        mockDuplicateStore = MockDuplicateSignatureStore()
        
        // Create hook with custom reporting callback to track blocked attachments
        downloadHook = AttachmentDownloadHook(
            signatureService: mockSignatureService,
            duplicateStore: mockDuplicateStore
        )
        
        // Install the hook with our mock database
        reportedBlockedAttachments.removeAll()
    }
    
    override func tearDown() async throws {
        mockSignatureService = nil
        mockDuplicateStore = nil
        downloadHook = nil
        reportedBlockedAttachments.removeAll()
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testDownloadHook_AllowsNonBlockedContent() async throws {
        // Arrange
        let testData = "test content".data(using: .utf8)!
        let attachment = MockAttachment(uniqueId: UUID().uuidString, contentType: "text/plain")
        attachment.mockDataForDownload = testData
        
        // Act
        let result = try await downloadHook.processDownloadedAttachment(attachment)
        
        // Assert
        XCTAssertTrue(result.allowDownload)
        XCTAssertNotNil(result.contentHash)
        XCTAssertFalse(mockSignatureService.blockedHashes.contains(result.contentHash!))
    }
    
    func testDownloadHook_BlocksGloballyBlockedContent() async throws {
        // Arrange
        let testData = "blocked content".data(using: .utf8)!
        let attachment = MockAttachment(uniqueId: UUID().uuidString, contentType: "text/plain")
        attachment.mockDataForDownload = testData
        
        // Calculate hash and add to blocked list
        let hash = try calculateContentHash(testData)
        mockSignatureService.blockedHashes.insert(hash)
        
        // Act
        let result = try await downloadHook.processDownloadedAttachment(attachment)
        
        // Assert
        XCTAssertFalse(result.allowDownload)
        XCTAssertEqual(result.contentHash, hash)
        XCTAssertEqual(result.blockReason, .globallyBlocked)
    }
    
    func testDownloadHook_BlocksLocallyBlockedContent() async throws {
        // Arrange
        let testData = "locally blocked".data(using: .utf8)!
        let attachment = MockAttachment(uniqueId: UUID().uuidString, contentType: "text/plain")
        attachment.mockDataForDownload = testData
        
        // Calculate hash and add to local blocked list
        let hash = try calculateContentHash(testData)
        mockDuplicateStore.blockedHashes.insert(hash)
        
        // Act
        let result = try await downloadHook.processDownloadedAttachment(attachment)
        
        // Assert
        XCTAssertFalse(result.allowDownload)
        XCTAssertEqual(result.contentHash, hash)
        XCTAssertEqual(result.blockReason, .locallyBlocked)
    }
    
    func testDownloadHook_HandlesEmptyContent() async throws {
        // Arrange
        let testData = Data()
        let attachment = MockAttachment(uniqueId: UUID().uuidString, contentType: "text/plain")
        attachment.mockDataForDownload = testData
        
        // Act
        let result = try await downloadHook.processDownloadedAttachment(attachment)
        
        // Assert
        XCTAssertTrue(result.allowDownload)
        XCTAssertNotNil(result.contentHash)
        XCTAssertEqual(result.contentHash, try calculateContentHash(testData))
    }
    
    func testDownloadHook_HandlesLargeContent() async throws {
        // Arrange
        let testData = Data(repeating: 0x41, count: 1024 * 1024) // 1MB of 'A's
        let attachment = MockAttachment(uniqueId: UUID().uuidString, contentType: "application/octet-stream")
        attachment.mockDataForDownload = testData
        
        // Act
        let result = try await downloadHook.processDownloadedAttachment(attachment)
        
        // Assert
        XCTAssertTrue(result.allowDownload)
        XCTAssertNotNil(result.contentHash)
        XCTAssertEqual(result.contentHash, try calculateContentHash(testData))
    }
    
    func testDownloadHook_HandlesInvalidData() async {
        // Arrange
        let attachment = MockAttachment(uniqueId: UUID().uuidString, contentType: "text/plain")
        attachment.mockDataForDownload = nil // This will cause dataForDownload() to throw
        
        // Act & Assert
        do {
            _ = try await downloadHook.processDownloadedAttachment(attachment)
            XCTFail("Should have thrown an error for invalid data")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateContentHash(_ data: Data) throws -> String {
        let sha256 = data.withUnsafeBytes { bytes in
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return sha256.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Mock Classes

/// A mock implementation of GlobalSignatureService for testing
class MockGlobalSignatureService {
    var blockedHashes = Set<String>()
    var storedHashes = Set<String>()
    var hashCheckCount = 0
    var shouldThrowError = false
    
    func contains(_ hash: String, retryCount: Int? = nil) async throws -> Bool {
        if shouldThrowError {
            throw NSError(domain: "MockSignatureService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Simulated service failure"])
        }
        
        hashCheckCount += 1
        return blockedHashes.contains(hash)
    }
    
    func store(_ hash: String, retryCount: Int? = nil) async -> Bool {
        storedHashes.insert(hash)
        blockedHashes.insert(hash) // Also mark as blocked for testing
        return true
    }
}

/// A mock DuplicateSignatureStore implementation for testing
class MockDuplicateSignatureStore {
    var blockedHashes = Set<String>()
    
    func isBlocked(_ hash: String) -> Bool {
        blockedHashes.contains(hash)
    }
}

/// A mock TSAttachment implementation for testing
class MockAttachment: TSAttachment {
    let uniqueId: String
    let contentType: String
    var mockDataForDownload: Data?
    
    init(uniqueId: String, contentType: String) {
        self.uniqueId = uniqueId
        self.contentType = contentType
    }
    
    override func dataForDownload() throws -> Data {
        guard let mockDataForDownload else {
            throw NSError(domain: "MockAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data available"])
        }
        return mockDataForDownload
    }
}

struct AttachmentProcessingResult {
    let allowDownload: Bool
    let contentHash: String
    let blockReason: BlockReason?
}

enum BlockReason {
    case locallyBlocked
    case globallyBlocked
}