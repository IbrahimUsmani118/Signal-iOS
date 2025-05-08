// In AttachmentDownloadHook.swift

import Foundation
import SignalServiceKit
import ObjectiveC

class AttachmentDownloadHook {
    static let shared = AttachmentDownloadHook()
    
    func install() {
        Logger.debug("Installing attachment download hooks for duplicate detection")
        
        // Hook into Signal's AttachmentDownloadManager
        setupAttachmentDownloadManagerHook()
        
        // Also add notification observer as a fallback
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePossibleAttachmentDownload(_:)),
            name: .attachmentDownloadDidSucceed, // Use an actual Signal notification name
            object: nil
        )
    }
    
    private func setupAttachmentDownloadManagerHook() {
        // We need to target AttachmentDownloadManager's method that's called after an attachment is downloaded
        // This is a guess based on common method naming - we'll need to find the actual method
        
        let originalClass: AnyClass = AttachmentDownloadManager.self
        
        let originalSelector = NSSelectorFromString("attachmentDownloadDidSucceed:")
        let swizzledSelector = #selector(AttachmentDownloadHook.handleAttachmentDownload(_:))
        
        guard let originalMethod = class_getInstanceMethod(originalClass, originalSelector),
              let swizzledMethod = class_getInstanceMethod(AttachmentDownloadHook.self, swizzledSelector) else {
            Logger.warn("Could not find methods to swizzle for duplicate detection")
            return
        }
        
        // Add our method to the original class
        let didAddMethod = class_addMethod(
            originalClass,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        
        if didAddMethod {
            // If we successfully added the method, now replace the original
            let replacement = class_getInstanceMethod(originalClass, swizzledSelector)!
            method_exchangeImplementations(originalMethod, replacement)
            Logger.debug("Successfully installed duplicate detection hook")
        } else {
            Logger.warn("Failed to install duplicate detection hook")
        }
    }
    
    @objc
    func handleAttachmentDownload(_ attachment: TSAttachment) {
        // Call original method (which is now this method due to swizzling)
        // Be careful with this to avoid recursive calls
        
        // Process the attachment for duplicate detection
        processAttachment(attachment)
    }
    
    @objc
    private func handlePossibleAttachmentDownload(_ notification: Notification) {
        guard let attachmentId = notification.userInfo?["attachmentId"] as? String else {
            return
        }
        
        // Look up the attachment
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                return
            }
            
            // Process the attachment
            self.processAttachment(attachment)
        }
    }
    
    private func processAttachment(_ attachment: TSAttachment) {
        guard DuplicateDetectionManager.shared.isEnabled else {
            return
        }
        
        // Only process image attachments that have been downloaded
        guard let attachmentStream = attachment as? TSAttachmentStream,
              attachmentStream.isImage,
              let filePath = attachmentStream.originalFilePath else {
            return
        }
        
        // Get the thread ID
        let threadId = attachment.uniqueThreadId ?? ""
        
        // Process for duplicate detection on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL = URL(fileURLWithPath: filePath)
            DuplicateDetector.shared.processIncomingImage(
                imageURL: fileURL,
                conversationId: threadId,
                attachmentId: attachment.uniqueId
            )
        }
    }
}