//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class StoryThumbnailView: UIView {
    enum Attachment: Equatable {
        case file(TSAttachment)
        case text(PreloadedTextAttachment)
        case missing

        static func from(_ storyMessage: StoryMessage, transaction: SDSAnyReadTransaction) -> Self {
            switch storyMessage.attachment {
            case .file, .foreignReferenceAttachment:
                guard
                    let attachment = storyMessage.fileAttachment(tx: transaction)?.bridge
                else {
                    owsFailDebug("Unexpectedly missing attachment for story")
                    return .missing
                }
                return .file(attachment)
            case .text(let attachment):
                return .text(.from(attachment, storyMessage: storyMessage, tx: transaction))
            }
        }
    }

    init(attachment: Attachment, interactionIdentifier: InteractionSnapshotIdentifier, spoilerState: SpoilerRenderState) {
        super.init(frame: .zero)

        layer.cornerRadius = 12
        clipsToBounds = true

        switch attachment {
        case .file(let attachment):
            if let pointer = attachment.asTransitTierPointer()?.bridgePointerAndNotStream {
                let pointerView = UIView()

                if let blurHashImageView = buildBlurHashImageViewIfAvailable(pointer: pointer) {
                    pointerView.addSubview(blurHashImageView)
                    blurHashImageView.autoPinEdgesToSuperviewEdges()
                }

                addSubview(pointerView)
                pointerView.autoPinEdgesToSuperviewEdges()
            } else if let stream = attachment.asResourceStream()?.bridgeStream {
                let imageView = buildThumbnailImageView(stream: stream)
                addSubview(imageView)
                imageView.autoPinEdgesToSuperviewEdges()
            } else {
                owsFailDebug("Unexpected attachment type \(type(of: attachment))")
            }
        case .text(let attachment):
            let textThumbnailView = TextAttachmentView(
                attachment: attachment,
                interactionIdentifier: interactionIdentifier,
                spoilerState: spoilerState
            ).asThumbnailView()
            addSubview(textThumbnailView)
            textThumbnailView.autoPinEdgesToSuperviewEdges()
        case .missing:
            // TODO: error state
            break
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildThumbnailImageView(stream: TSAttachmentStream) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true

        applyThumbnailImage(to: imageView, for: stream)

        return imageView
    }

    private static let thumbnailCache = LRUCache<String, UIImage>(maxSize: 64, shouldEvacuateInBackground: true)
    private func applyThumbnailImage(to imageView: UIImageView, for stream: TSAttachmentStream) {
        if let thumbnailImage = Self.thumbnailCache[stream.uniqueId] {
            imageView.image = thumbnailImage
        } else {
            stream.thumbnailImageSmall { thumbnailImage in
                imageView.image = thumbnailImage
                Self.thumbnailCache.setObject(thumbnailImage, forKey: stream.uniqueId)
            } failure: {
                owsFailDebug("Failed to generate thumbnail")
            }
        }
    }

    private func buildBlurHashImageViewIfAvailable(pointer: TSAttachmentPointer) -> UIView? {
        guard let blurHash = pointer.blurHash, let blurHashImage = BlurHash.image(for: blurHash) else {
            return nil
        }
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        imageView.image = blurHashImage
        return imageView
    }
}
