//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TSResourceStore {

    func fetch(
        _ ids: [Attachment.IDType],
        tx: DBReadTransaction
    ) -> [Attachment]

    // MARK: - Message Attachment fetching

    /// Includes all types: media, long text, voice message, stickers,
    /// quoted reply thumbnails, link preview images, contact avatars.
    func allAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [AttachmentReference]

    /// Includes media, long text, and voice message attachments.
    /// Excludes stickers, quoted reply thumbnails, link preview images, contact avatars.
    func bodyAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [AttachmentReference]

    /// Includes media and voice message attachments.
    /// Excludes long text, stickers, quoted reply thumbnails, link preview images, contact avatars.
    func bodyMediaAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [AttachmentReference]

    func oversizeTextAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference?

    func contactShareAvatarAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference?

    func linkPreviewAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference?

    func stickerAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference?

    // MARK: - Quoted Messages

    func quotedAttachmentReference(
        from info: OWSAttachmentInfo,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> TSQuotedMessageResourceReference?

    func attachmentToUseInQuote(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference?

    // MARK: - Story Message Attachment Fetching

    func mediaAttachment(
        for storyMessage: StoryMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference?

    func linkPreviewAttachment(
        for storyMessage: StoryMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference?
}

// MARK: - Convenience

extension TSResourceStore {

    public func fetch(
        _ id: Attachment.IDType,
        tx: DBReadTransaction
    ) -> Attachment? {
        return fetch([id], tx: tx).first
    }

    public func quotedAttachmentReference(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> TSQuotedMessageResourceReference? {
        guard let info = message.quotedMessage?.attachmentInfo() else {
            return nil
        }
        return quotedAttachmentReference(from: info, parentMessage: message, tx: tx)
    }

    public func quotedThumbnailAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference? {
        let ref = self.quotedAttachmentReference(for: message, tx: tx)
        switch ref {
        case .thumbnail(let attachmentRef):
            return attachmentRef
        case .stub, nil:
            return nil
        }
    }

    // MARK: - Referenced Attachments

    public func referencedBodyAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [ReferencedAttachment] {
        let references = self.bodyAttachments(for: message, tx: tx)
        let attachments = Dictionary(
            grouping: self.fetch(references.map(\.attachmentRowId), tx: tx),
            by: \.id
        )
        return references.compactMap { reference -> ReferencedAttachment? in
            guard let attachment = attachments[reference.attachmentRowId]?.first else {
                owsFailDebug("Missing attachment!")
                return nil
            }
            return ReferencedAttachment(reference: reference, attachment: attachment)
        }
    }

    public func referencedBodyMediaAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [ReferencedAttachment] {
        let references = self.bodyMediaAttachments(for: message, tx: tx)
        let attachments = Dictionary(
            grouping: self.fetch(references.map(\.attachmentRowId), tx: tx),
            by: \.id
        )
        return references.compactMap { reference -> ReferencedAttachment? in
            guard let attachment = attachments[reference.attachmentRowId]?.first else {
                owsFailDebug("Missing attachment!")
                return nil
            }
            return ReferencedAttachment(reference: reference, attachment: attachment)
        }
    }
}
