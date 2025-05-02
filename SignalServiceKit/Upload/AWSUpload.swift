import Foundation
import AWSS3
import AWSDynamoDB
import SignalCoreKit

/// A class that implements the `UploadProtocol` for AWS S3 uploads.
/// This class handles file uploads to AWS S3 and stores associated metadata in DynamoDB.
/// It supports both small and large file uploads with progress tracking, retry logic,
/// and duplicate detection across devices.
public class AWSUpload: UploadProtocol {
    private let awsService: AWSUploadService
    private let deviceId: String
    
    /// Initializes a new AWS upload instance.
    /// - Parameters:
    ///   - deviceId: The unique identifier for the current device
    /// - Throws: `OWSAssertionError` if AWS configuration is missing or invalid
    public init(deviceId: String) throws {
        self.awsService = try AWSUploadService()
        self.deviceId = deviceId
    }
    
    /// Uploads a file to AWS S3 and stores its metadata in DynamoDB.
    /// - Parameters:
    ///   - attempt: The upload attempt containing file and metadata information
    ///   - progress: A callback to track upload progress
    /// - Returns: A result containing upload information
    /// - Throws: `Upload.Error` if the upload fails
    public func upload(
        _ attempt: Upload.Attempt<Upload.LocalUploadMetadata>,
        progress: @escaping (Progress) -> Void
    ) async throws -> Upload.Result<Upload.LocalUploadMetadata> {
        // Create progress object
        let uploadProgress = Progress(totalUnitCount: 100)
        progress(uploadProgress)
        
        do {
            // Calculate file hash (10% of progress)
            uploadProgress.completedUnitCount = 10
            let fileHash = try await calculateFileHash(attempt.fileUrl)
            
            // Upload to S3 (80% of progress)
            uploadProgress.completedUnitCount = 20
            let s3Key = try await awsService.uploadFile(
                attempt.fileUrl,
                hash: fileHash
            ) { partProgress in
                // Scale part progress to fit within the 20-90% range
                let scaledProgress = 20 + (partProgress.fractionCompleted * 70)
                uploadProgress.completedUnitCount = Int64(scaledProgress * 100)
                progress(uploadProgress)
            }
            uploadProgress.completedUnitCount = 90
            
            // Store metadata in DynamoDB (10% of progress)
            try await awsService.storeMetadata(
                hash: fileHash,
                s3Key: s3Key,
                fileSize: Int64(attempt.encryptedDataLength),
                deviceId: deviceId
            )
            uploadProgress.completedUnitCount = 100
            
            // Return result
            return Upload.Result(
                cdnKey: s3Key,
                cdnNumber: 0, // AWS S3 doesn't use CDN numbers
                localUploadMetadata: attempt.localMetadata,
                beginTimestamp: attempt.beginTimestamp,
                finishTimestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            )
        } catch let error as OWSAssertionError {
            // Convert OWSAssertionError to Upload.Error
            throw Upload.Error.uploadFailure(recovery: .restart(.afterBackoff))
        } catch {
            // Handle other errors
            throw Upload.Error.uploadFailure(recovery: .restart(.afterBackoff))
        }
    }
    
    /// Calculates the SHA-256 hash of a file.
    /// - Parameter fileURL: The URL of the file to hash
    /// - Returns: The hexadecimal string representation of the hash
    /// - Throws: `OWSAssertionError` if the file cannot be read or hashed
    private func calculateFileHash(_ fileURL: URL) async throws -> String {
        do {
            let data = try Data(contentsOf: fileURL)
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            throw OWSAssertionError("Failed to calculate file hash: \(error.localizedDescription)")
        }
    }
}

// MARK: - UploadProtocol

public protocol UploadProtocol {
    /// Uploads a file and returns the result.
    /// - Parameters:
    ///   - attempt: The upload attempt containing file and metadata information
    ///   - progress: A callback to track upload progress
    /// - Returns: A result containing upload information
    /// - Throws: `Upload.Error` if the upload fails
    func upload(
        _ attempt: Upload.Attempt<Upload.LocalUploadMetadata>,
        progress: @escaping (Progress) -> Void
    ) async throws -> Upload.Result<Upload.LocalUploadMetadata>
} 