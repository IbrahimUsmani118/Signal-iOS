import XCTest
import Foundation
import AWSDynamoDB
import AWSS3

class DuplicateContentTests: XCTestCase {
    private let testQueue = DispatchQueue(label: "com.signal.duplicatecontent.tests", attributes: .concurrent)
    private let testDataSize = 1024 * 1024 // 1MB
    
    override func setUp() {
        super.setUp()
        DebugConfig.shared.enableVerboseLogging = true
        DebugConfig.shared.enablePerformanceLogging = true
        DebugConfig.shared.enableValidationChecks = true
        DebugConfig.shared.enableCacheDebugging = true
        DebugConfig.shared.enableDetailedValidation = true
        DebugConfig.shared.enableResourceMonitoring = true
        DebugConfig.shared.enableErrorTracking = true
        DebugConfig.shared.enableCacheValidation = true
        DebugConfig.shared.enableDataIntegrityChecks = true
        DebugConfig.shared.enableNetworkLatencyMonitoring = true
    }
    
    override func tearDown() {
        super.tearDown()
        DebugLogger.shared.clearLogs()
        PerformanceMonitor.shared.reset()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testContentValidation() async throws {
        let data = generateTestData(size: testDataSize)
        let result = try await ContentValidator.shared.validateContentWithChecks(data)
        
        XCTAssertFalse(result.isValid, "New content should not be valid")
        XCTAssertEqual(result.source, .none, "Source should be none for new content")
        XCTAssertGreaterThan(result.duration, 0, "Validation should take some time")
        XCTAssertFalse(result.checks.isEmpty, "Should have validation checks")
    }
    
    func testCacheHit() async throws {
        let data = generateTestData(size: testDataSize)
        let hash = ContentValidator.shared.calculateHash(data)
        
        // Add to cache
        SignatureCache.shared.addSignature(hash, forHash: hash)
        
        let result = try await ContentValidator.shared.validateContentWithChecks(data)
        
        XCTAssertTrue(result.isValid, "Content should be valid after cache hit")
        XCTAssertEqual(result.source, .cache, "Source should be cache")
        
        // Verify cache check
        let cacheCheck = result.checks.first { $0.type == .cache }
        XCTAssertNotNil(cacheCheck, "Should have cache check")
        XCTAssertTrue(cacheCheck?.isValid ?? false, "Cache check should be valid")
    }
    
    func testDataIntegrity() async throws {
        // Test empty data
        let emptyData = Data()
        let emptyResult = try await ContentValidator.shared.validateContentWithChecks(emptyData)
        XCTAssertFalse(emptyResult.isValid, "Empty data should be invalid")
        
        // Test corrupted image data
        let corruptedImage = generateCorruptedImageData()
        let corruptedResult = try await ContentValidator.shared.validateContentWithChecks(corruptedImage)
        XCTAssertFalse(corruptedResult.isValid, "Corrupted image should be invalid")
        
        // Test valid data
        let validData = generateTestData(size: testDataSize)
        let validResult = try await ContentValidator.shared.validateContentWithChecks(validData)
        XCTAssertTrue(validResult.checks.first { $0.type == .dataIntegrity }?.isValid ?? false,
                     "Valid data should pass integrity check")
    }
    
    // MARK: - Performance Tests
    
    func testValidationPerformance() async throws {
        let data = generateTestData(size: testDataSize)
        let iterations = 100
        
        var totalDuration: TimeInterval = 0
        var minDuration: TimeInterval = .infinity
        var maxDuration: TimeInterval = 0
        
        for i in 0..<iterations {
            let startTime = Date()
            _ = try await ContentValidator.shared.validateContentWithChecks(data)
            let duration = Date().timeIntervalSince(startTime)
            
            totalDuration += duration
            minDuration = min(minDuration, duration)
            maxDuration = max(maxDuration, duration)
            
            if i % 10 == 0 {
                DebugLogger.shared.log("Validation \(i)/\(iterations) completed")
            }
        }
        
        let averageDuration = totalDuration / Double(iterations)
        DebugLogger.shared.log("Validation Performance:")
        DebugLogger.shared.log("Average: \(String(format: "%.3f", averageDuration))s")
        DebugLogger.shared.log("Min: \(String(format: "%.3f", minDuration))s")
        DebugLogger.shared.log("Max: \(String(format: "%.3f", maxDuration))s")
        
        XCTAssertLessThan(averageDuration, 0.5, "Average validation time should be less than 500ms")
        XCTAssertLessThan(maxDuration, 1.0, "Maximum validation time should be less than 1s")
    }
    
    func testConcurrentValidation() async throws {
        let data = generateTestData(size: testDataSize)
        let concurrentCount = 10
        
        let startTime = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrentCount {
                group.addTask {
                    _ = try await ContentValidator.shared.validateContentWithChecks(data)
                }
            }
            try await group.waitForAll()
        }
        let totalDuration = Date().timeIntervalSince(startTime)
        
        DebugLogger.shared.log("Concurrent Validation Performance:")
        DebugLogger.shared.log("Total Duration: \(String(format: "%.3f", totalDuration))s")
        DebugLogger.shared.log("Operations: \(concurrentCount)")
        
        XCTAssertLessThan(totalDuration, 2.0, "Concurrent validation should complete within 2 seconds")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() async throws {
        // Test network error simulation
        let data = generateTestData(size: testDataSize)
        
        do {
            // Simulate network error
            AWSManager.shared.simulateNetworkError = true
            _ = try await ContentValidator.shared.validateContentWithChecks(data)
            XCTFail("Should have thrown network error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("network"), "Should be a network error")
        } finally {
            AWSManager.shared.simulateNetworkError = false
        }
        
        // Test invalid data handling
        let invalidData = Data([0xFF, 0xD8, 0xFF]) // Invalid JPEG header
        let result = try await ContentValidator.shared.validateContentWithChecks(invalidData)
        XCTAssertFalse(result.isValid, "Invalid data should be rejected")
    }
    
    // MARK: - Resource Monitoring Tests
    
    func testResourceMonitoring() async throws {
        let data = generateTestData(size: testDataSize)
        let iterations = 50
        
        // Record initial metrics
        let initialMemory = PerformanceMonitor.shared.getMemoryUsage()
        let initialThreads = PerformanceMonitor.shared.getThreadCount()
        
        for i in 0..<iterations {
            _ = try await ContentValidator.shared.validateContentWithChecks(data)
            
            if i % 10 == 0 {
                PerformanceMonitor.shared.recordMemoryUsage()
                PerformanceMonitor.shared.recordThreadCount()
            }
        }
        
        // Get final metrics
        let finalMemory = PerformanceMonitor.shared.getMemoryUsage()
        let finalThreads = PerformanceMonitor.shared.getThreadCount()
        
        DebugLogger.shared.log("Resource Monitoring Results:")
        DebugLogger.shared.log("Memory Usage:")
        DebugLogger.shared.log("Initial: \(initialMemory) bytes")
        DebugLogger.shared.log("Final: \(finalMemory) bytes")
        DebugLogger.shared.log("Thread Count:")
        DebugLogger.shared.log("Initial: \(initialThreads)")
        DebugLogger.shared.log("Final: \(finalThreads)")
        
        // Check for memory leaks
        XCTAssertLessThan(finalMemory - initialMemory, 10 * 1024 * 1024,
                         "Memory usage should not increase significantly")
        
        // Check for thread leaks
        XCTAssertLessThanOrEqual(finalThreads - initialThreads, 2,
                                "Thread count should not increase significantly")
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData(size: Int) -> Data {
        var data = Data(count: size)
        _ = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        return data
    }
    
    private func generateCorruptedImageData() -> Data {
        var data = Data([0xFF, 0xD8, 0xFF]) // Partial JPEG header
        data.append(generateTestData(size: 100)) // Add some random data
        return data
    }
}

// MARK: - AWSManager Extension for Testing

extension AWSManager {
    var simulateNetworkError: Bool {
        get { false }
        set {
            // Implementation for simulating network errors
            // This would be implemented in the actual AWSManager class
        }
    }
} 