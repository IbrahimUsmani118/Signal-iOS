import Foundation
import CocoaLumberjack

public class ImageService {
    
    // MARK: - Types
    
    public enum ImageServiceError: Error {
        case uploadFailed(String)
        case getTagFailed(String)
        case blockImageFailed(String)
        case invalidImageData
        case networkError(Error)
        case invalidResponse
        case authenticationFailed
    }
    
    // MARK: - Properties
    
    public static let shared = ImageService()
    
    private let session: URLSession
    private let s3Service: S3Service
    
    private var logger: DDLog {
        return DDLog.sharedInstance
    }
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AWSConfig.requestTimeoutSeconds
        config.timeoutIntervalForResource = AWSConfig.resourceTimeoutSeconds
        self.session = URLSession(configuration: config)
        self.s3Service = S3Service.shared
    }
    
    // MARK: - Public Methods
    
    /// Uploads an image to S3 and returns the URL
    /// - Parameter imageData: The image data to upload
    /// - Returns: URL of the uploaded image
    public func uploadImage(imageData: Data) async throws -> URL {
        guard !imageData.isEmpty else {
            throw ImageServiceError.invalidImageData
        }
        
        let fileName = generateUniqueFileName()
        let key = "\(AWSConfig.s3ImagesPath)\(fileName)"
        
        do {
            _ = try await s3Service.uploadFile(
                fileData: imageData,
                key: key,
                contentType: "image/jpeg"
            )
            
            guard let url = URL(string: "\(AWSConfig.s3BaseURL)\(fileName)") else {
                throw ImageServiceError.uploadFailed("Failed to create image URL")
            }
            
            return url
        } catch let error as S3Service.S3ServiceError {
            Logger.error("S3 upload failed: \(error)")
            throw ImageServiceError.uploadFailed("S3 upload failed: \(error)")
        } catch {
            Logger.error("Unknown error during upload: \(error)")
            throw ImageServiceError.networkError(error)
        }
    }
    
    /// Gets the tag for an image using the API Gateway endpoint
    /// - Parameter imageURL: URL of the image to get the tag for
    /// - Returns: Tag string
    public func getImageTag(imageURL: URL) async throws -> String {
        let request = createAPIRequest(url: AWSConfig.getTagAPIURL, apiKey: AWSConfig.getTagAPIKey)
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "imageUrl": imageURL.absoluteString
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            var urlRequest = request
            urlRequest.httpBody = jsonData
            
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImageServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tag = jsonResponse["tag"] as? String {
                    return tag
                } else {
                    throw ImageServiceError.getTagFailed("Invalid response format")
                }
                
            case 401, 403:
                throw ImageServiceError.authenticationFailed
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ImageServiceError.getTagFailed("API error: \(httpResponse.statusCode), \(errorMessage)")
            }
        } catch let error as ImageServiceError {
            throw error
        } catch {
            throw ImageServiceError.networkError(error)
        }
    }
    
    /// Blocks an image using the API Gateway endpoint
    /// - Parameter imageURL: URL of the image to block
    public func blockImage(imageURL: URL) async throws {
        let request = createAPIRequest(url: AWSConfig.blockImageAPIURL, apiKey: AWSConfig.blockImageAPIKey)
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "imageUrl": imageURL.absoluteString
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            var urlRequest = request
            urlRequest.httpBody = jsonData
            
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImageServiceError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return
                
            case 401, 403:
                throw ImageServiceError.authenticationFailed
                
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ImageServiceError.blockImageFailed("API error: \(httpResponse.statusCode), \(errorMessage)")
            }
        } catch let error as ImageServiceError {
            throw error
        } catch {
            throw ImageServiceError.networkError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func generateUniqueFileName() -> String {
        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(uuid)-\(timestamp).jpg"
    }
    
    private func createAPIRequest(url: String, apiKey: String) -> URLRequest {
        guard let url = URL(string: url) else {
            fatalError("Invalid API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Add AWS auth headers if needed
        if !AWSConfig.accessKeyId.isEmpty && !AWSConfig.secretAccessKey.isEmpty {
            request.setValue(AWSConfig.accessKeyId, forHTTPHeaderField: "X-Amz-Security-Token")
            // In a real implementation, you would properly sign the request with AWS Signature v4
        }
        
        return request
    }
} 