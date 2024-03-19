//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Restoring an outgoing message from a backup isn't any different from learning about
/// an outgoing message sent on a linked device and synced to the local device.
///
/// So we represent restored messages as "transcripts" that we can plug into the same
/// transcript processing pipes as synced message transcripts.
internal class RestoredSentMessageTranscript: SentMessageTranscript {

    private let messageParams: SentMessageTranscriptType.Message

    var type: SentMessageTranscriptType {
        return .message(messageParams)
    }

    let timestamp: UInt64

    // Not applicable
    var requiredProtocolVersion: UInt32? { nil }

    let recipientStates: [MessageBackup.InteropAddress: TSOutgoingMessageRecipientState]

    internal static func from(
        chatItem: BackupProtoChatItem,
        contents: MessageBackup.RestoredMessageContents,
        outgoingDetails: BackupProtoChatItemOutgoingMessageDetails,
        context: MessageBackup.ChatRestoringContext,
        thread: MessageBackup.ChatThread
    ) -> MessageBackup.RestoreInteractionResult<RestoredSentMessageTranscript> {

        let expirationDuration = UInt32(chatItem.expiresInMs / 1000)

        let target: SentMessageTranscriptTarget
        switch thread {
        case .contact(let contactThread):
            target = .contact(contactThread, .token(forProtoExpireTimer: expirationDuration))
        case .groupV2(let groupThread):
            target = .group(groupThread)
        }

        // TODO: handle attachments in quotes
        let quotedMessageBuilder = contents.quotedMessage.map {
            return OwnedAttachmentBuilder<TSQuotedMessage>.withoutFinalizer($0)
        }

        let messageParams = SentMessageTranscriptType.Message(
            target: target,
            body: contents.body?.text,
            bodyRanges: contents.body?.ranges,
            // TODO: attachments
            attachmentPointerProtos: [],
            quotedMessageBuilder: quotedMessageBuilder,
            // TODO: contact message
            contact: nil,
            // TODO: linkPreview message
            linkPreviewBuilder: nil,
            // TODO: gift badge message
            giftBadge: nil,
            // TODO: sticker message
            messageSticker: nil,
            // TODO: isViewOnceMessage
            isViewOnceMessage: false,
            expirationStartedAt: chatItem.expireStartDate,
            expirationDuration: expirationDuration,
            // We never restore stories.
            storyTimestamp: nil,
            storyAuthorAci: nil
        )

        var partialErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]()

        var recipientStates = [MessageBackup.InteropAddress: TSOutgoingMessageRecipientState]()
        for sendStatus in outgoingDetails.sendStatus {
            let recipientAddress: MessageBackup.InteropAddress
            switch context.recipientContext[chatItem.authorRecipientId] {
            case .contact(let address):
                recipientAddress = address.asInteropAddress()
            case .none:
                // Missing recipient! Fail this one recipient but keep going.
                partialErrors.append(.invalidProtoData(
                    chatItem.id,
                    .recipientIdNotFound(chatItem.authorRecipientId)
                ))
                continue
            case .localAddress, .group:
                // Recipients can only be contacts.
                partialErrors.append(.invalidProtoData(
                    chatItem.id,
                    .outgoingNonContactMessageRecipient
                ))
                continue
            }

            guard
                let recipientState = recipientState(
                    for: sendStatus,
                    partialErrors: &partialErrors,
                    chatItemId: chatItem.id
                )
            else {
                continue
            }

            recipientStates[recipientAddress] = recipientState
        }

        if recipientStates.isEmpty && outgoingDetails.sendStatus.isEmpty.negated {
            // We put up with some failures, but if we get no recipients at all
            // fail the whole thing.
            return .messageFailure(partialErrors)
        }

        let transcript = RestoredSentMessageTranscript(
            messageParams: messageParams,
            timestamp: chatItem.dateSent,
            recipientStates: recipientStates
        )
        if partialErrors.isEmpty {
            return .success(transcript)
        } else {
            return .partialRestore(transcript, partialErrors)
        }
    }

    private static func recipientState(
        for sendStatus: BackupProtoSendStatus,
        partialErrors: inout [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>],
        chatItemId: MessageBackup.ChatItemId
    ) -> TSOutgoingMessageRecipientState? {
        guard let recipientState = TSOutgoingMessageRecipientState() else {
            partialErrors.append(.databaseInsertionFailed(
                chatItemId,
                OWSAssertionError("Unable to create recipient state!")
            ))
            return nil
        }

        recipientState.wasSentByUD = sendStatus.sealedSender.negated

        switch sendStatus.deliveryStatus {
        case .none, .unknown:
            partialErrors.append(.invalidProtoData(chatItemId, .unrecognizedMessageSendStatus))
            return nil
        case .pending:
            recipientState.state = .pending
            recipientState.errorCode = nil
            return recipientState
        case .sent:
            recipientState.state = .sent
            recipientState.errorCode = nil
            return recipientState
        case .delivered:
            recipientState.state = .sent
            recipientState.deliveryTimestamp = NSNumber(value: sendStatus.lastStatusUpdateTimestamp)
            recipientState.errorCode = nil
            return recipientState
        case .read:
            recipientState.state = .sent
            recipientState.readTimestamp = NSNumber(value: sendStatus.lastStatusUpdateTimestamp)
            recipientState.errorCode = nil
            return recipientState
        case .viewed:
            recipientState.state = .sent
            recipientState.viewedTimestamp = NSNumber(value: sendStatus.lastStatusUpdateTimestamp)
            recipientState.errorCode = nil
            return recipientState
        case .skipped:
            recipientState.state = .skipped
            recipientState.errorCode = nil
            return recipientState
        case .failed:
            recipientState.state = .failed
            if sendStatus.identityKeyMismatch {
                // We want to explicitly represent identity key errors.
                // Other types we don't really care about.
                recipientState.errorCode = NSNumber(value: UntrustedIdentityError.errorCode)
            } else {
                recipientState.errorCode = NSNumber(value: OWSErrorCode.genericFailure.rawValue)
            }
            return recipientState
        }
    }

    private init(
        messageParams: SentMessageTranscriptType.Message,
        timestamp: UInt64,
        recipientStates: [MessageBackup.InteropAddress: TSOutgoingMessageRecipientState]
    ) {
        self.messageParams = messageParams
        self.timestamp = timestamp
        self.recipientStates = recipientStates
    }
}
