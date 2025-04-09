// DuplicateDetection/AttachmentProcessor.swift

import Foundation
import SignalServiceKit
import SignalUI

class AttachmentProcessor {
    static let shared = AttachmentProcessor()
    
    func setup() {
        Logger.debug("Setting up AttachmentProcessor for duplicate detection")
        
        // Register for attachment download notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAttachmentDownloaded(_:)),
            name: .attachmentDownloadJobCompleted, // We'll need to find the correct notification name
            object: nil
        )
        
        // Listen for our own duplicate detection notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDuplicateImageDetected(_:)),
            name: DuplicateDetector.duplicateImageDetectedNotification,
            object: nil
        )
        
        // Listen for blocked image notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBlockedImageDetected(_:)),
            name: DuplicateDetector.blockedImageDetectedNotification,
            object: nil
        )
        
        Logger.info("AttachmentProcessor setup complete")
    }
    
    @objc
    private func handleAttachmentDownloaded(_ notification: Notification) {
        // Get the attachment from the notification
        guard DuplicateDetectionManager.shared.isEnabled,
              let attachmentID = notification.userInfo?["attachmentId"] as? String else {
            return
        }
        
        Logger.debug("Handling downloaded attachment with ID: \(attachmentID)")
        
        // Process on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentID, transaction: transaction),
                      let attachmentStream = attachment as? TSAttachmentStream,
                      attachmentStream.isImage,
                      let filePath = attachmentStream.originalFilePath else {
                    return
                }
                
                // Get the thread ID
                let threadId = attachment.uniqueThreadId ?? ""
                
                Logger.debug("Processing image attachment in thread: \(threadId)")
                
                // Process for duplicate detection
                let fileURL = URL(fileURLWithPath: filePath)
                DuplicateDetector.shared.processIncomingImage(
                    imageURL: fileURL,
                    conversationId: threadId,
                    attachmentId: attachmentID
                )
            }
        }
    }
    
    @objc
    private func handleDuplicateImageDetected(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let count = userInfo["count"] as? Int,
              let hash = userInfo["hash"] as? String,
              let conversationId = userInfo["conversationId"] as? String,
              let imageURL = userInfo["imageURL"] as? URL else {
            return
        }
        
        Logger.info("Duplicate image detected with hash: \(hash) in conversation: \(conversationId)")
        
        // Show alert on main thread
        DispatchQueue.main.async {
            let body = "This image appears similar to \(count) image(s) you've seen before."
            let notificationTitle = "Duplicate Image Detected"
            
            let actionSheet = ActionSheetController(title: notificationTitle, message: body)
            
            // Add option to block this image
            let blockAction = ActionSheetAction(title: "Block This Image", style: .destructive) { _ in
                Logger.info("User chose to block image with hash: \(hash)")
                DuplicateDetector.shared.blockImageHash(hash)
                OWSActionSheets.showActionSheet(title: "Image Blocked", message: "This image has been added to your block list.")
            }
            actionSheet.addAction(blockAction)
            
            // Add option to view details
            let detailsAction = ActionSheetAction(title: "View Details", style: .default) { _ in
                // This would ideally navigate to a detailed view of the duplicate
                // For now, we just show a simple alert with the hash
                Logger.debug("User requested details for hash: \(hash)")
                OWSActionSheets.showActionSheet(
                    title: "Image Details",
                    message: "Image hash: \(hash)\nFound in \(count) conversations"
                )
            }
            actionSheet.addAction(detailsAction)
            
            // Add dismiss option
            let dismissAction = ActionSheetAction(title: "Dismiss", style: .cancel)
            actionSheet.addAction(dismissAction)
            
            // Present the action sheet
            UIApplication.shared.frontmostViewController?.presentActionSheet(actionSheet)
        }
    }
    
    @objc
    private func handleBlockedImageDetected(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let hash = userInfo["hash"] as? String,
              let conversationId = userInfo["conversationId"] as? String else {
            return
        }
        
        Logger.info("Blocked image detected with hash: \(hash) in conversation: \(conversationId)")
        
        // Show alert on main thread
        DispatchQueue.main.async {
            let body = "An image you previously blocked was detected and filtered."
            let notificationTitle = "Blocked Image Detected"
            
            let actionSheet = ActionSheetController(title: notificationTitle, message: body)
            
            // Add option to unblock this image
            let unblockAction = ActionSheetAction(title: "Unblock This Image", style: .default) { _ in
                Logger.info("User chose to unblock image with hash: \(hash)")
                DuplicateDetector.shared.unblockImageHash(hash)
                OWSActionSheets.showActionSheet(title: "Image Unblocked", message: "This image has been removed from your block list.")
            }
            actionSheet.addAction(unblockAction)
            
            // Add dismiss option
            let dismissAction = ActionSheetAction(title: "Keep Blocked", style: .cancel)
            actionSheet.addAction(dismissAction)
            
            // Present the action sheet
            UIApplication.shared.frontmostViewController?.presentActionSheet(actionSheet)
        }
    }
}