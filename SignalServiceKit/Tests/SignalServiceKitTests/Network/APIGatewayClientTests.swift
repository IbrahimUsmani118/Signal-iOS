import XCTest
import AWSCore
import SignalCore
import Logging

class APIGatewayClientTests: XCTestCase {
    // MARK: - Properties
    
    private var client: APIGatewayClient!
    private var mockConnectionManager: MockConnectionManager!
    private var mockCredentialCache: MockCredentialCache!
    private var mockPerformanceMetrics: MockPerformanceMetrics!
    
    // MARK: - Setup
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockConnectionManager = MockConnectionManager()
        mockCredentialCache = MockCredentialCache()
        mockPerformanceMetrics = MockPerformanceMetrics()
        
        client = APIGatewayClient(
            connectionManager: mockConnectionManager,
            credentialCache: mockCredentialCache,
            performanceMetrics: mockPerformanceMetrics
        )
    }
    
    // MARK: - Tests
    
    func testSuccessfulRequest() async throws {
        // Setup
        let testData = "Test response".data(using: .utf8)!
        mockConnectionManager.mockResponse = testData
        mockCredentialCache.mockCredentials = AWSCredentials(
            accessKey: "test-key",
            secretKey: "test-secret",
            sessionToken: "test-token",
            expiration: Date().addingTimeInterval(3600)
        )
        
        // Execute
        let response = try await client.request(
            endpoint: "https://api.example.com/test",
            method: .get,
            headers: ["Content-Type": "application/json"]
        )
        
        // Verify
        XCTAssertEqual(response, testData)
        XCTAssertEqual(mockConnectionManager.lastServiceName, "APIGateway")
        XCTAssertEqual(mockConnectionManager.lastOperationName, "GET https://api.example.com/test")
        XCTAssertEqual(mockPerformanceMetrics.recordedMetrics.count, 1)
        XCTAssertTrue(mockPerformanceMetrics.recordedMetrics[0].success)
    }
    
    func testRequestWithQueryParams() async throws {
        // Setup
        let testData = "Test response".data(using: .utf8)!
        mockConnectionManager.mockResponse = testData
        mockCredentialCache.mockCredentials = AWSCredentials(
            accessKey: "test-key",
            secretKey: "test-secret",
            sessionToken: "test-token",
            expiration: Date().addingTimeInterval(3600)
        )
        
        // Execute
        let response = try await client.request(
            endpoint: "https://api.example.com/test",
            method: .get,
            queryParams: ["param1": "value1", "param2": "value2"]
        )
        
        // Verify
        XCTAssertEqual(response, testData)
        XCTAssertEqual(mockConnectionManager.lastServiceName, "APIGateway")
        XCTAssertEqual(mockConnectionManager.lastOperationName, "GET https://api.example.com/test")
    }
    
    func testRequestWithBody() async throws {
        // Setup
        let testData = "Test response".data(using: .utf8)!
        let requestBody = "Request body".data(using: .utf8)!
        mockConnectionManager.mockResponse = testData
        mockCredentialCache.mockCredentials = AWSCredentials(
            accessKey: "test-key",
            secretKey: "test-secret",
            sessionToken: "test-token",
            expiration: Date().addingTimeInterval(3600)
        )
        
        // Execute
        let response = try await client.request(
            endpoint: "https://api.example.com/test",
            method: .post,
            body: requestBody
        )
        
        // Verify
        XCTAssertEqual(response, testData)
        XCTAssertEqual(mockConnectionManager.lastServiceName, "APIGateway")
        XCTAssertEqual(mockConnectionManager.lastOperationName, "POST https://api.example.com/test")
    }
    
    func testMissingCredentials() async throws {
        // Setup
        mockCredentialCache.mockCredentials = nil
        
        // Execute & Verify
        do {
            _ = try await client.request(endpoint: "https://api.example.com/test")
            XCTFail("Should have thrown missing credentials error")
        } catch let error as APIGatewayError {
            XCTAssertEqual(error, .missingCredentials)
        }
    }
    
    func testRequestRetry() async throws {
        // Setup
        let testData = "Test response".data(using: .utf8)!
        mockConnectionManager.mockResponse = testData
        mockConnectionManager.shouldFailFirstAttempt = true
        mockCredentialCache.mockCredentials = AWSCredentials(
            accessKey: "test-key",
            secretKey: "test-secret",
            sessionToken: "test-token",
            expiration: Date().addingTimeInterval(3600)
        )
        
        // Execute
        let response = try await client.request(endpoint: "https://api.example.com/test")
        
        // Verify
        XCTAssertEqual(response, testData)
        XCTAssertEqual(mockConnectionManager.attemptCount, 2)
    }
    
    func testPerformanceMetrics() async throws {
        // Setup
        let testData = "Test response".data(using: .utf8)!
        mockConnectionManager.mockResponse = testData
        mockCredentialCache.mockCredentials = AWSCredentials(
            accessKey: "test-key",
            secretKey: "test-secret",
            sessionToken: "test-token",
            expiration: Date().addingTimeInterval(3600)
        )
        
        // Execute
        _ = try await client.request(
            endpoint: "https://api.example.com/test",
            method: .post,
            body: "Request body".data(using: .utf8)
        )
        
        // Verify
        XCTAssertEqual(mockPerformanceMetrics.recordedMetrics.count, 1)
        let metric = mockPerformanceMetrics.recordedMetrics[0]
        XCTAssertEqual(metric.service, "APIGateway")
        XCTAssertEqual(metric.operation, "POST https://api.example.com/test")
        XCTAssertTrue(metric.success)
        XCTAssertNotNil(metric.requestSize)
        XCTAssertNotNil(metric.responseSize)
    }
}

// MARK: - Mock Types

private class MockConnectionManager: AWSConnectionManager {
    var mockResponse: Data?
    var shouldFailFirstAttempt = false
    var attemptCount = 0
    var lastServiceName: String?
    var lastOperationName: String?
    
    override func executeWithRetry<T>(
        _ operation: () async throws -> T,
        serviceName: String,
        operationName: String
    ) async throws -> T {
        lastServiceName = serviceName
        lastOperationName = operationName
        attemptCount += 1
        
        if shouldFailFirstAttempt && attemptCount == 1 {
            throw NSError(domain: "Test", code: -1)
        }
        
        if let response = mockResponse as? T {
            return response
        }
        
        throw NSError(domain: "Test", code: -1)
    }
}

private class MockCredentialCache: AWSCredentialCache {
    var mockCredentials: AWSCredentials?
    
    override func getCredentials(forService service: String) throws -> AWSCredentials? {
        return mockCredentials
    }
}

private class MockPerformanceMetrics: AWSPerformanceMetrics {
    var recordedMetrics: [Metric] = []
    
    override func recordMetric(
        service: String,
        operation: String,
        duration: TimeInterval,
        success: Bool,
        error: Error? = nil,
        requestSize: Int? = nil,
        responseSize: Int? = nil
    ) {
        recordedMetrics.append(Metric(
            service: service,
            operation: operation,
            duration: duration,
            timestamp: Date(),
            success: success,
            error: error,
            requestSize: requestSize,
            responseSize: responseSize
        ))
    }
}
