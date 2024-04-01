//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// Represents a _playable_ audio attachment.
public class AudioAttachment {
    public enum State: Equatable {
        case attachmentStream(attachmentStream: TSAttachmentStream, isVoiceMessage: Bool, audioDurationSeconds: TimeInterval)
        case attachmentPointer(attachmentPointer: TSAttachmentPointer, isVoiceMessage: Bool)
    }
    public let state: State
    public let owningMessage: TSMessage?

    // Set at time of init. Value doesn't change even after download completes
    // to ensure that conversation view diffing catches the need to redraw the cell
    public let isDownloading: Bool

    public init?(
        attachment: TSAttachment,
        owningMessage: TSMessage?,
        metadata: MediaMetadata?,
        isVoiceMessage: Bool
    ) {
        if let attachmentStream = attachment as? TSAttachmentStream {
            let audioDurationSeconds = attachmentStream.audioDurationSeconds()
            guard audioDurationSeconds > 0 else {
                return nil
            }
            state = .attachmentStream(attachmentStream: attachmentStream, isVoiceMessage: isVoiceMessage, audioDurationSeconds: audioDurationSeconds)
            isDownloading = false
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            state = .attachmentPointer(attachmentPointer: attachmentPointer, isVoiceMessage: isVoiceMessage)

            switch attachmentPointer.state {
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                isDownloading = false
            case .enqueued, .downloading:
                isDownloading = true
            }
        } else {
            owsFailDebug("Invalid attachment.")
            return nil
        }

        self.owningMessage = owningMessage
    }
}

extension AudioAttachment: Dependencies {
    var isDownloaded: Bool { attachmentStream != nil }

    public var attachment: TSAttachment {
        switch state {
        case .attachmentStream(let attachmentStream, _, _):
            return attachmentStream
        case .attachmentPointer(let attachmentPointer, _):
            return attachmentPointer
        }
    }

    public var attachmentStream: TSAttachmentStream? {
        switch state {
        case .attachmentStream(let attachmentStream, _, _):
            return attachmentStream
        case .attachmentPointer:
            return nil
        }
    }

    public var attachmentPointer: TSAttachmentPointer? {
        switch state {
        case .attachmentStream:
            return nil
        case .attachmentPointer(let attachmentPointer, _):
            return attachmentPointer
        }
    }

    public var durationSeconds: TimeInterval {
        switch state {
        case .attachmentStream(_, _, let audioDurationSeconds):
            return audioDurationSeconds
        case .attachmentPointer:
            return 0
        }
    }

    public var isVoiceMessage: Bool {
        switch state {
        case .attachmentStream(_, let isVoiceMessage, _):
            return isVoiceMessage
        case .attachmentPointer(_, let isVoiceMessage):
            return isVoiceMessage
        }
    }

    public func markOwningMessageAsViewed() -> Bool {
        AssertIsOnMainThread()
        guard let incomingMessage = owningMessage as? TSIncomingMessage, !incomingMessage.wasViewed else { return false }
        databaseStorage.asyncWrite { tx in
            let uniqueId = incomingMessage.uniqueId
            guard
                let latestMessage = TSIncomingMessage.anyFetchIncomingMessage(uniqueId: uniqueId, transaction: tx),
                let latestThread = latestMessage.thread(tx: tx)
            else {
                return
            }
            let circumstance: OWSReceiptCircumstance = (
                latestThread.hasPendingMessageRequest(transaction: tx)
                ? .onThisDeviceWhilePendingMessageRequest
                : .onThisDevice
            )
            latestMessage.markAsViewed(
                atTimestamp: Date.ows_millisecondTimestamp(),
                thread: latestThread,
                circumstance: circumstance,
                transaction: tx
            )
        }
        return true
    }
}

extension AudioAttachment: Equatable {
    public static func == (lhs: AudioAttachment, rhs: AudioAttachment) -> Bool {
        lhs.state == rhs.state &&
        lhs.owningMessage == rhs.owningMessage &&
        lhs.isDownloading == rhs.isDownloading
    }
}
