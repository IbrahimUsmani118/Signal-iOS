import Foundation
import UIKit
import SignalServiceKit

/// Main class for detecting duplicate images
class DuplicateDetector {
    private let hashDatabase = HashDatabase.getInstance()
    private let notificationCenter = NotificationCenter.default
    
    static let shared = DuplicateDetector()
    
    // Notification names
    static let duplicateImageDetectedNotification = Notification.Name("org.signal.duplicateImageDetected")
    static let blockedImageDetectedNotification = Notification.Name("org.signal.blockedImageDetected")
    
    /// Process an incoming image to detect duplicates and blocked content
    func processIncomingImage(imageURL: URL, conversationId: String, attachmentId: String? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Skip processing if feature is disabled
            guard DuplicateDetectionManager.shared.isEnabled else {
                return
            }
            
            // Calculate hash of the image
            guard let hash = ImageHasher.calculateImageHash(from: imageURL) else {
                Logger.error("Failed to calculate hash for image at \(imageURL)")
                return
            }
            
            Logger.debug("Generated hash \(hash) for image at \(imageURL)")
            
            // First check if this image is blocked
            if self.hashDatabase.isSignatureBlocked(hash) {
                Logger.info("Detected blocked image with hash: \(hash)")
                
                // Notify that a blocked image was detected
                let userInfo: [AnyHashable: Any] = [
                    "hash": hash,
                    "conversationId": conversationId,
                    "imageURL": imageURL
                ]
                
                DispatchQueue.main.async {
                    self.notificationCenter.post(
                        name: DuplicateDetector.blockedImageDetectedNotification,
                        object: nil,
                        userInfo: userInfo
                    )
                }
                
                // Still add to database for record-keeping
                let filename = imageURL.lastPathComponent
                _ = self.hashDatabase.addImageHash(
                    hash: hash,
                    conversationId: conversationId,
                    attachmentId: attachmentId,
                    filename: filename
                )
                
                return
            }
            
            // Check for similar images
            let threshold = DuplicateDetectionManager.shared.getSimilarityThreshold()
            let similarImages = self.hashDatabase.findSimilarImages(hash: hash, threshold: threshold)
            
            // If similar images found, notify the user
            if !similarImages.isEmpty {
                Logger.info("Found \(similarImages.count) similar images for hash: \(hash)")
                
                let userInfo: [AnyHashable: Any] = [
                    "count": similarImages.count,
                    "hash": hash,
                    "conversationId": conversationId,
                    "imageURL": imageURL,
                    "similarImages": similarImages
                ]
                
                DispatchQueue.main.async {
                    self.notificationCenter.post(
                        name: DuplicateDetector.duplicateImageDetectedNotification, 
                        object: nil, 
                        userInfo: userInfo
                    )
                }
            }
            
            // Add the hash to the database regardless of whether it's a duplicate
            let filename = imageURL.lastPathComponent
            _ = self.hashDatabase.addImageHash(
                hash: hash, 
                conversationId: conversationId, 
                attachmentId: attachmentId, 
                filename: filename
            )
        }
    }
    
    /// Check if an image is blocked based on its hash
    func isImageBlocked(imageURL: URL) -> Bool {
        guard DuplicateDetectionManager.shared.isEnabled else {
            return false
        }
        
        guard let hash = ImageHasher.calculateImageHash(from: imageURL) else {
            return false
        }
        
        return hashDatabase.isSignatureBlocked(hash)
    }
    
    /// Block an image by its URL
    func blockImage(imageURL: URL) -> Bool {
        guard let hash = ImageHasher.calculateImageHash(from: imageURL) else {
            return false
        }
        
        return hashDatabase.blockSignature(hash)
    }
    
    /// Block an image by its hash
    func blockImageHash(_ hash: String) -> Bool {
        return hashDatabase.blockSignature(hash)
    }
    
    /// Unblock an image by its hash
    func unblockImageHash(_ hash: String) -> Bool {
        return hashDatabase.unblockSignature(hash)
    }
    
    /// Perform maintenance - clean up old data
    func performMaintenance() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // Get storage duration from settings
            let maxAgeDays = DuplicateDetectionManager.shared.getStorageDuration()
            let cutoffDate = Calendar.current.date(
                byAdding: .day,
                value: -maxAgeDays,
                to: Date()
            ) ?? Date()
            
            // Clear old hashes
            let deletedCount = self.hashDatabase.clearOldHashes(olderThan: cutoffDate)
            Logger.debug("Maintenance complete: removed \(deletedCount) old hash entries")
        }
    }
    
    /// Clear all stored hashes
    func clearAllHashes() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let count = self.hashDatabase.deleteAllHashes()
            Logger.debug("Cleared \(count) hash entries")
        }
    }
    
    /// Clear all non-blocked hashes
    func clearNonBlockedHashes() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let count = self.hashDatabase.clearNonBlockedHashes()
            Logger.debug("Cleared \(count) non-blocked hash entries")
        }
    }
}