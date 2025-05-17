import Foundation
import SignalServiceKit
import CocoaLumberjack

/// Client for interacting with AWS API Gateway
public class APIGatewayClient {
    
    // MARK: - Types
    
    public enum APIGatewayError: Error {
        case requestFailed(String)
        case invalidResponse
        case serializationError
        case networkError(Error)
        case authenticationFailed
    }
    
    // MARK: - Properties
    
    public static let shared = APIGatewayClient()
    
    private let session: URLSession
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AWSConfig.requestTimeoutSeconds
        config.timeoutIntervalForResource = AWSConfig.resourceTimeoutSeconds
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Performs a GET request to the API Gateway
    /// - Parameters:
    ///   - endpoint: Full API endpoint URL
    ///   - apiKey: API key (optional)
    ///   - headers: Additional headers (optional)
    /// - Returns: Response data
    public func get(
        endpoint: String,
        apiKey: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        return try await request(
            endpoint: endpoint,
            method: "GET",
            apiKey: apiKey,
            headers: headers
        )
    }
    
    /// Performs a POST request to the API Gateway
    /// - Parameters:
    ///   - endpoint: Full API endpoint URL
    ///   - body: Request body (will be JSON serialized)
    ///   - apiKey: API key (optional)
    ///   - headers: Additional headers (optional)
    /// - Returns: Response data
    public func post(
        endpoint: String,
        body: [String: Any],
        apiKey: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw APIGatewayError.serializationError
        }
        
        return try await request(
            endpoint: endpoint,
            method: "POST",
            body: jsonData,
            apiKey: apiKey,
            headers: headers
        )
    }
    
    /// Performs a PUT request to the API Gateway
    /// - Parameters:
    ///   - endpoint: Full API endpoint URL
    ///   - body: Request body (will be JSON serialized)
    ///   - apiKey: API key (optional)
    ///   - headers: Additional headers (optional)
    /// - Returns: Response data
    public func put(
        endpoint: String,
        body: [String: Any],
        apiKey: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw APIGatewayError.serializationError
        }
        
        return try await request(
            endpoint: endpoint,
            method: "PUT",
            body: jsonData,
            apiKey: apiKey,
            headers: headers
        )
    }
    
    /// Performs a DELETE request to the API Gateway
    /// - Parameters:
    ///   - endpoint: Full API endpoint URL
    ///   - apiKey: API key (optional)
    ///   - headers: Additional headers (optional)
    /// - Returns: Response data
    public func delete(
        endpoint: String,
        apiKey: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        return try await request(
            endpoint: endpoint,
            method: "DELETE",
            apiKey: apiKey,
            headers: headers
        )
    }
    
    // MARK: - Private Methods
    
    private func request(
        endpoint: String,
        method: String,
        body: Data? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw APIGatewayError.requestFailed("Invalid URL: \(endpoint)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Set default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Set API key if provided
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        
        // Add AWS auth headers if needed
        if !AWSConfig.accessKeyId.isEmpty && !AWSConfig.secretAccessKey.isEmpty {
            request.setValue(AWSConfig.accessKeyId, forHTTPHeaderField: "X-Amz-Security-Token")
            // In a real implementation, you would properly sign the request with AWS Signature v4
        }
        
        // Add custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Set body for POST/PUT requests
        if let body = body {
            request.httpBody = body
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIGatewayError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return data
                
            case 401, 403:
                throw APIGatewayError.authenticationFailed
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIGatewayError.requestFailed("API error: \(httpResponse.statusCode), \(errorMessage)")
            }
        } catch let error as APIGatewayError {
            throw error
        } catch {
            throw APIGatewayError.networkError(error)
        }
    }
} 