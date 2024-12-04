//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceDownloadManagerImpl: TSResourceDownloadManager {

    private let attachmentDownloadManager: AttachmentDownloadManager
    private let tsResourceStore: TSResourceStore

    public init(
        attachmentDownloadManager: AttachmentDownloadManager,
        tsResourceStore: TSResourceStore
    ) {
        self.attachmentDownloadManager = attachmentDownloadManager
        self.tsResourceStore = tsResourceStore

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(v2AttachmentProgressNotification(_:)),
            name: AttachmentDownloads.attachmentDownloadProgressNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: AttachmentDownloads.attachmentDownloadProgressNotification,
            object: nil
        )
    }

    @objc
    private func v2AttachmentProgressNotification(_ notification: Notification) {
        /// Forward all v2 notifications as v1 notifications.
        guard
            let rowId = notification.userInfo?[AttachmentDownloads.attachmentDownloadAttachmentIDKey] as? Attachment.IDType,
            let progress = notification.userInfo?[AttachmentDownloads.attachmentDownloadProgressKey] as? CGFloat
        else {
            return
        }
        NotificationCenter.default.post(
            name: TSResourceDownloads.attachmentDownloadProgressNotification,
            object: nil,
            userInfo: [
                TSResourceDownloads.attachmentDownloadAttachmentIDKey: TSResourceId.v2(rowId: rowId),
                TSResourceDownloads.attachmentDownloadProgressKey: progress
            ]
        )
    }

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        let resources = tsResourceStore.allAttachments(for: message, tx: tx)
        if resources.isEmpty.negated {
            attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(message, priority: priority, tx: tx)
        }
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(message, priority: priority, tx: tx)
    }

    public func cancelDownload(for attachmentId: TSResourceId, tx: DBWriteTransaction) {
        switch attachmentId {
        case .v2(let rowId):
            attachmentDownloadManager.cancelDownload(for: rowId, tx: tx)
        }
    }

    public func downloadProgress(for attachmentId: TSResourceId, tx: DBReadTransaction) -> CGFloat? {
        switch attachmentId {
        case .v2(let rowId):
            return attachmentDownloadManager.downloadProgress(for: rowId, tx: tx)
        }
    }
}
