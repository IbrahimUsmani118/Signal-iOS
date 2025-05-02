import Foundation
import AWSCore
import SignalCore
import Logging

/// Client for interacting with AWS API Gateway
class APIGatewayClient {
    // MARK: - Properties
    
    private let logger: Logger
    private let connectionManager: AWSConnectionManager
    private let credentialCache: AWSCredentialCache
    private let performanceMetrics: AWSPerformanceMetrics
    
    // MARK: - Initialization
    
    init(
        connectionManager: AWSConnectionManager = AWSConnectionManager(),
        credentialCache: AWSCredentialCache = AWSCredentialCache(),
        performanceMetrics: AWSPerformanceMetrics = AWSPerformanceMetrics()
    ) {
        self.connectionManager = connectionManager
        self.credentialCache = credentialCache
        self.performanceMetrics = performanceMetrics
        self.logger = Logger(label: "org.signal.APIGatewayClient")
    }
    
    // MARK: - Public Methods
    
    /// Makes a request to API Gateway
    /// - Parameters:
    ///   - endpoint: The API endpoint
    ///   - method: HTTP method
    ///   - headers: Request headers
    ///   - body: Request body
    ///   - queryParams: Query parameters
    /// - Returns: Response data
    /// - Throws: Error if request fails
    func request(
        endpoint: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        queryParams: [String: String] = [:]
    ) async throws -> Data {
        let startTime = Date()
        var error: Error?
        
        do {
            let result = try await connectionManager.executeWithRetry(
                {
                    try await self.executeRequest(
                        endpoint: endpoint,
                        method: method,
                        headers: headers,
                        body: body,
                        queryParams: queryParams
                    )
                },
                serviceName: "APIGateway",
                operationName: "\(method.rawValue) \(endpoint)"
            )
            
            let duration = Date().timeIntervalSince(startTime)
            performanceMetrics.recordMetric(
                service: "APIGateway",
                operation: "\(method.rawValue) \(endpoint)",
                duration: duration,
                success: true,
                requestSize: body?.count,
                responseSize: result.count
            )
            
            return result
        } catch let requestError {
            error = requestError
            let duration = Date().timeIntervalSince(startTime)
            performanceMetrics.recordMetric(
                service: "APIGateway",
                operation: "\(method.rawValue) \(endpoint)",
                duration: duration,
                success: false,
                error: requestError,
                requestSize: body?.count
            )
            throw requestError
        }
    }
    
    // MARK: - Private Methods
    
    private func executeRequest(
        endpoint: String,
        method: HTTPMethod,
        headers: [String: String],
        body: Data?,
        queryParams: [String: String]
    ) async throws -> Data {
        // Get credentials
        guard let credentials = try credentialCache.getCredentials(forService: "APIGateway") else {
            throw APIGatewayError.missingCredentials
        }
        
        // Create URL with query parameters
        var urlComponents = URLComponents(string: endpoint)!
        if !queryParams.isEmpty {
            urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        // Create request
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = method.rawValue
        request.httpBody = body
        
        // Add headers
        var allHeaders = headers
        allHeaders["Authorization"] = "Bearer \(credentials.sessionToken ?? "")"
        allHeaders["x-api-key"] = credentials.accessKey
        allHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIGatewayError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIGatewayError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }
}

// MARK: - Supporting Types

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

enum APIGatewayError: Error {
    case missingCredentials
    case invalidResponse
    case httpError(statusCode: Int)
    case requestFailed(Error)
    
    var localizedDescription: String {
        switch self {
        case .missingCredentials:
            return "Missing API Gateway credentials"
        case .invalidResponse:
            return "Invalid response from API Gateway"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        }
    }
}
