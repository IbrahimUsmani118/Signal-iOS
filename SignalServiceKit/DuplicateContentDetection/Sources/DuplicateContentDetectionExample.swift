import Foundation
import UIKit

/// Example class demonstrating how to use the duplicate content detection system
public class DuplicateContentDetectionExample {
    
    private let detectionManager = DuplicateContentDetectionManager.shared
    private let awsManager = AWSManager.shared
    
    /// Example: Checks if an image is a duplicate
    /// - Parameter image: UIImage to check
    /// - Returns: Result indicating whether the image is a duplicate
    public func checkForDuplicateImage(_ image: UIImage) async -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return "Failed to get image data"
        }
        
        let result = await detectionManager.checkForDuplicateImage(imageData: imageData)
        
        switch result {
        case .unique:
            return "Image is unique and has been added to the detection system"
            
        case .duplicate(let tag):
            return "Image is a duplicate with tag: \(tag)"
            
        case .error(let error):
            return "Error checking image: \(error.localizedDescription)"
        }
    }
    
    /// Example: Blocks an image
    /// - Parameter image: UIImage to block
    /// - Returns: Result message
    public func blockImage(_ image: UIImage) async -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return "Failed to get image data"
        }
        
        let success = await detectionManager.blockImage(imageData: imageData)
        
        if success {
            return "Image has been successfully blocked"
        } else {
            return "Failed to block image"
        }
    }
    
    /// Example: Checks if text is a duplicate
    /// - Parameter text: Text to check
    /// - Returns: Result message
    public func checkForDuplicateText(_ text: String) async -> String {
        let result = await detectionManager.checkForDuplicateText(text)
        
        switch result {
        case .unique:
            return "Text is unique and has been added to the detection system"
            
        case .duplicate(let hash):
            return "Text is a duplicate with hash: \(hash)"
            
        case .error(let error):
            return "Error checking text: \(error.localizedDescription)"
        }
    }
    
    /// Example: Verifies AWS credentials and services
    /// - Returns: Verification report message
    public func verifyAWSServices() async -> String {
        let report = await awsManager.verifyAWSCredentials()
        
        var resultMessage = "AWS Services Verification Report:\n"
        resultMessage += "- AWS Credentials: \(report.awsCredentialsValid ? "Valid" : "Invalid")\n"
        resultMessage += "- S3 Access: \(report.s3Accessible ? "Available" : "Unavailable")\n"
        resultMessage += "- DynamoDB Access: \(report.dynamoDBAccessible ? "Available" : "Unavailable")\n"
        resultMessage += "- API Gateway Access: \(report.apiGatewayAccessible ? "Available" : "Unavailable")\n"
        
        if !report.errors.isEmpty {
            resultMessage += "\nErrors:\n"
            for error in report.errors {
                resultMessage += "- \(error)\n"
            }
        }
        
        return resultMessage
    }
    
    /// Example: Demonstrates uploading an image to S3
    /// - Parameter image: UIImage to upload
    /// - Returns: URL of the uploaded image
    public func uploadImageExample(_ image: UIImage) async -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return "Failed to get image data"
        }
        
        do {
            let imageURL = try await ImageService.shared.uploadImage(imageData: imageData)
            return "Image uploaded successfully. URL: \(imageURL.absoluteString)"
        } catch {
            return "Failed to upload image: \(error.localizedDescription)"
        }
    }
    
    /// Example: Demonstrates retrieving an image tag
    /// - Parameter imageURL: URL of the image to get the tag for
    /// - Returns: Tag of the image
    public func getImageTagExample(imageURL: URL) async -> String {
        do {
            let tag = try await ImageService.shared.getImageTag(imageURL: imageURL)
            return "Image tag: \(tag)"
        } catch {
            return "Failed to get image tag: \(error.localizedDescription)"
        }
    }
    
    /// Example: Demonstrates storing a content hash in DynamoDB
    /// - Parameter hash: Hash to store
    /// - Returns: Result message
    public func storeHashExample(hash: String) async -> String {
        do {
            let success = try await DynamoDBService.shared.storeContentHash(hash)
            return success ? "Hash stored successfully" : "Failed to store hash"
        } catch {
            return "Error storing hash: \(error.localizedDescription)"
        }
    }
    
    /// Example: Demonstrates checking if a hash exists in DynamoDB
    /// - Parameter hash: Hash to check
    /// - Returns: Result message
    public func checkHashExistsExample(hash: String) async -> String {
        do {
            let exists = try await DynamoDBService.shared.doesContentHashExist(hash)
            return exists ? "Hash exists in the database" : "Hash does not exist in the database"
        } catch {
            return "Error checking hash: \(error.localizedDescription)"
        }
    }
} 