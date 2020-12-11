//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentGenericAttachment: CVComponentBase, CVComponent {

    private let genericAttachment: CVComponentState.GenericAttachment
    private var attachment: TSAttachment { genericAttachment.attachment }
    private var attachmentStream: TSAttachmentStream? { genericAttachment.attachmentStream }
    private var attachmentPointer: TSAttachmentPointer? { genericAttachment.attachmentPointer }

    init(itemModel: CVItemModel, genericAttachment: CVComponentState.GenericAttachment) {
        self.genericAttachment = genericAttachment

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewGenericAttachment()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewGenericAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let hStackView = componentView.hStackView
        hStackView.apply(config: hStackConfig)

        if let downloadView = tryToBuildDownloadView() {
            hStackView.addArrangedSubview(downloadView)
        } else {
            let iconImageView = componentView.iconImageView
            if let icon = UIImage(named: "generic-attachment") {
                owsAssertDebug(icon.size == iconSize)
                iconImageView.image = icon
            } else {
                owsFailDebug("Missing icon.")
            }
            iconImageView.autoSetDimensions(to: iconSize)
            iconImageView.setCompressionResistanceHigh()
            iconImageView.setContentHuggingHigh()
            hStackView.addArrangedSubview(iconImageView)

            let fileTypeLabel = componentView.fileTypeLabel
            fileTypeLabelConfig.applyForRendering(label: fileTypeLabel)
            fileTypeLabel.adjustsFontSizeToFitWidth = true
            fileTypeLabel.minimumScaleFactor = 0.25
            fileTypeLabel.textAlignment = .center
            // Center on icon.
            iconImageView.addSubview(fileTypeLabel)
            fileTypeLabel.autoCenterInSuperview()
            fileTypeLabel.autoSetDimension(.width, toSize: iconSize.width - 15)
        }

        let vStackView = componentView.vStackView
        vStackView.apply(config: vStackViewConfig)
        hStackView.addArrangedSubview(vStackView)

        let topLabel = componentView.topLabel
        topLabelConfig.applyForRendering(label: topLabel)
        vStackView.addArrangedSubview(topLabel)

        let bottomLabel = componentView.bottomLabel
        bottomLabelConfig.applyForRendering(label: bottomLabel)
        vStackView.addArrangedSubview(bottomLabel)

        let accessibilityDescription = NSLocalizedString("ACCESSIBILITY_LABEL_ATTACHMENT",
                                                         comment: "Accessibility label for attachment.")
        hStackView.accessibilityLabel = accessibilityLabel(description: accessibilityDescription)
    }

    public override func incompleteAttachmentInfo(componentView: CVComponentView) -> IncompleteAttachmentInfo? {
        return incompleteAttachmentInfoIfNecessary(attachment: attachment,
                                                   attachmentView: componentView.rootView)
    }

    private var hStackLayoutMargins: UIEdgeInsets {
        return UIEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
    }

    private var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: hSpacing,
                          layoutMargins: hStackLayoutMargins)
    }

    private var vStackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .leading,
                          spacing: labelVSpacing,
                          layoutMargins: .zero)
    }

    private var topLabelConfig: CVLabelConfig {
        var text: String = attachment.sourceFilename?.ows_stripped() ?? ""
        if text.isEmpty,
           let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: attachment.contentType) {
            text = (fileExtension as NSString).localizedUppercase
        }
        if text.isEmpty {
            text = NSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeBody,
                             textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
                             lineBreakMode: .byTruncatingMiddle)
    }

    private var bottomLabelConfig: CVLabelConfig {
        var fileSize: UInt = 0
        if let attachmentStream = attachmentStream,
           let originalFilePath = attachmentStream.originalFilePath,
           let nsFileSize = OWSFileSystem.fileSize(ofPath: originalFilePath) {
            fileSize = nsFileSize.uintValue
        }

        // We don't want to show the file size while the attachment is downloading.
        // To avoid layout jitter when the download completes, we reserve space in
        // the layout using a whitespace string.
        var text = " "
        if fileSize > 0 {
            text = OWSFormat.formatFileSize(fileSize)
        }

        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeCaption1,
                             textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming),
                             lineBreakMode: .byTruncatingMiddle)
    }

    private var fileTypeLabelConfig: CVLabelConfig {
        var filename: String = attachment.sourceFilename ?? ""
        if filename.isEmpty,
           let attachmentStream = attachmentStream,
           let originalFilePath = attachmentStream.originalFilePath {
            filename = (originalFilePath as NSString).lastPathComponent
        }
        var fileExtension: String = (filename as NSString).pathExtension
        if fileExtension.isEmpty {
            fileExtension = MIMETypeUtil.fileExtension(forMIMEType: attachment.contentType) ?? ""
        }
        let text = (fileExtension as NSString).localizedUppercase

        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeCaption1.ows_semibold,
                             textColor: .ows_gray90,
                             lineBreakMode: .byTruncatingTail)
    }

    private func tryToBuildDownloadView() -> UIView? {
        guard let attachmentPointer = self.attachmentPointer else {
            return nil
        }

        switch attachmentPointer.state {
        case .failed:
            // We don't need to handle the "tap to retry" state here,
            // only download progress.
            return nil
        case .enqueued, .downloading, .pendingMessageRequest:
            break
        @unknown default:
            owsFailDebug("Invalid value.")
            return nil
        }

        switch attachmentPointer.pointerType {
        case .restoring:
            // TODO: Show "restoring" indicator and possibly progress.
            return nil
        case .unknown, .incoming:
            break
        @unknown default:
            owsFailDebug("Invalid value.")
            return nil
        }
        let attachmentId = attachmentPointer.uniqueId

        let downloadViewSize = min(iconSize.width, iconSize.height)
        let radius = downloadViewSize * 0.5
        let downloadView = MediaDownloadView(attachmentId: attachmentId, radius: radius)
        downloadView.autoSetDimensions(to: CGSize(square: downloadViewSize))
        downloadView.setCompressionResistanceHigh()
        downloadView.setContentHuggingHigh()
        return downloadView
    }

    private let hSpacing: CGFloat = 8
    private let labelVSpacing: CGFloat = 2
    private let iconSize = CGSize(width: 36, height: CGFloat(kStandardAvatarSize))

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let labelsHeight = (topLabelConfig.font.lineHeight +
                                bottomLabelConfig.font.lineHeight + labelVSpacing)
        let contentHeight = max(iconSize.height, labelsHeight)
        let height = contentHeight + hStackLayoutMargins.totalHeight

        let maxLabelWidth = max(0, maxWidth - (iconSize.width + hSpacing + hStackLayoutMargins.totalWidth))
        let topLabelSize = CVText.measureLabel(config: topLabelConfig, maxWidth: maxLabelWidth)
        let bottomLabelSize = CVText.measureLabel(config: bottomLabelConfig, maxWidth: maxLabelWidth)
        let labelsWidth = max(topLabelSize.width, bottomLabelSize.width)
        let contentWidth = iconSize.width + labelsWidth + hSpacing
        let width = min(maxLabelWidth, contentWidth)

        return CGSize(width: width, height: height).ceil
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let attachmentStream = attachmentStream else {
            return false
        }
        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        if attachmentStream.contentType == OWSMimeTypePdf {
            componentDelegate.cvc_didTapPdf(itemViewModel: itemViewModel,
                                            attachmentStream: attachmentStream)
        } else {
            // TODO: Ensure share UI is shown from correct location.
            AttachmentSharing.showShareUI(forAttachment: attachmentStream, sender: componentView.rootView)
        }
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewGenericAttachment: NSObject, CVComponentView {

        fileprivate let hStackView = OWSStackView(name: "GenericAttachment.hStackView")
        fileprivate let vStackView = OWSStackView(name: "GenericAttachment.vStackView")
        fileprivate let topLabel = UILabel()
        fileprivate let bottomLabel = UILabel()
        fileprivate let fileTypeLabel = UILabel()
        fileprivate let iconImageView = UIImageView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hStackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            hStackView.reset()
            vStackView.reset()
            topLabel.text = nil
            bottomLabel.text = nil
            fileTypeLabel.text = nil
            iconImageView.image = nil
        }
    }
}
