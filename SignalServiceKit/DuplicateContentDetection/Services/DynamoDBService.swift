import Foundation
import CocoaLumberjack

public class DynamoDBService {
    
    // MARK: - Types
    
    public enum DynamoDBServiceError: Error {
        case putItemFailed(String)
        case getItemFailed(String)
        case deleteItemFailed(String)
        case queryFailed(String)
        case invalidResponse
        case networkError(Error)
        case authenticationFailed
        case itemNotFound
        case serializationError
    }
    
    // MARK: - Properties
    
    public static let shared = DynamoDBService()
    
    private let session: URLSession
    private let tableName: String
    private let endpoint: String
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AWSConfig.requestTimeoutSeconds
        config.timeoutIntervalForResource = AWSConfig.resourceTimeoutSeconds
        self.session = URLSession(configuration: config)
        self.tableName = AWSConfig.hashTableName
        self.endpoint = AWSConfig.dynamoDBEndpoint
    }
    
    // MARK: - Public Methods
    
    /// Stores a content hash in DynamoDB
    /// - Parameters:
    ///   - contentHash: Hash of the content to store
    ///   - ttlInDays: Time to live in days (default: 30)
    /// - Returns: Success flag
    public func storeContentHash(_ contentHash: String, ttlInDays: Int = AWSConfig.defaultTTLInDays) async throws -> Bool {
        let apiURL = "\(endpoint)/content-hash"
        var request = createAPIRequest(url: apiURL)
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let ttl = timestamp + (ttlInDays * 24 * 60 * 60) // TTL in seconds
        
        let requestBody: [String: Any] = [
            AWSConfig.hashFieldName: contentHash,
            AWSConfig.timestampFieldName: timestamp,
            AWSConfig.ttlFieldName: ttl
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DynamoDBServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return true
                
            case 401, 403:
                throw DynamoDBServiceError.authenticationFailed
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw DynamoDBServiceError.putItemFailed("API error: \(httpResponse.statusCode), \(errorMessage)")
            }
        } catch let error as DynamoDBServiceError {
            throw error
        } catch {
            throw DynamoDBServiceError.networkError(error)
        }
    }
    
    /// Checks if a content hash exists in DynamoDB
    /// - Parameter contentHash: Hash to check
    /// - Returns: Whether the hash exists
    public func doesContentHashExist(_ contentHash: String) async throws -> Bool {
        let apiURL = "\(endpoint)/content-hash/\(contentHash)"
        let request = createAPIRequest(url: apiURL, method: "GET")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DynamoDBServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                // Item exists
                return true
                
            case 404:
                // Item not found
                return false
                
            case 401, 403:
                throw DynamoDBServiceError.authenticationFailed
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw DynamoDBServiceError.getItemFailed("API error: \(httpResponse.statusCode), \(errorMessage)")
            }
        } catch let error as DynamoDBServiceError {
            throw error
        } catch {
            throw DynamoDBServiceError.networkError(error)
        }
    }
    
    /// Deletes a content hash from DynamoDB
    /// - Parameter contentHash: Hash to delete
    /// - Returns: Success flag
    public func deleteContentHash(_ contentHash: String) async throws -> Bool {
        let apiURL = "\(endpoint)/content-hash/\(contentHash)"
        let request = createAPIRequest(url: apiURL, method: "DELETE")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DynamoDBServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return true
                
            case 404:
                // Item not found is not an error for delete operation
                return true
                
            case 401, 403:
                throw DynamoDBServiceError.authenticationFailed
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw DynamoDBServiceError.deleteItemFailed("API error: \(httpResponse.statusCode), \(errorMessage)")
            }
        } catch let error as DynamoDBServiceError {
            throw error
        } catch {
            throw DynamoDBServiceError.networkError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createAPIRequest(url: String, method: String = "POST") -> URLRequest {
        guard let url = URL(string: url) else {
            fatalError("Invalid API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add API key if available
        if !AWSConfig.apiKey.isEmpty {
            request.setValue(AWSConfig.apiKey, forHTTPHeaderField: "x-api-key")
        }
        
        // Add AWS auth headers if needed
        if !AWSConfig.accessKeyId.isEmpty && !AWSConfig.secretAccessKey.isEmpty {
            request.setValue(AWSConfig.accessKeyId, forHTTPHeaderField: "X-Amz-Security-Token")
            // In a real implementation, you would properly sign the request with AWS Signature v4
        }
        
        return request
    }
} 