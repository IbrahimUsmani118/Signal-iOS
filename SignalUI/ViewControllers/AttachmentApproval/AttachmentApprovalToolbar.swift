//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging
import UIKit

class AttachmentApprovalToolbar: UIView {

    struct Configuration: Equatable {
        var isAddMoreVisible = true
        var isMediaStripVisible = false
        var canToggleViewOnce = true
        var canChangeMediaQuality = true
        var canSaveMedia = false
        var doneButtonAssetResourceName = "send-solid-24"

        static func == (lhs: Self, rhs: Self) -> Bool {
            if lhs.isAddMoreVisible != rhs.isAddMoreVisible {
                return false
            }
            if lhs.isMediaStripVisible != rhs.isMediaStripVisible {
                return false
            }
            if lhs.canToggleViewOnce != rhs.canToggleViewOnce {
                return false
            }
            if lhs.canChangeMediaQuality != rhs.canChangeMediaQuality {
                return false
            }
            if lhs.canSaveMedia != rhs.canSaveMedia {
                return false
            }
            if lhs.doneButtonAssetResourceName != rhs.doneButtonAssetResourceName {
                return false
            }
            return true
        }
    }

    var configuration: Configuration

    // Only visible when there's one media item and contains "Add Media" and "View Once" buttons.
    // Displayed in place of galleryRailView.
    private lazy var singleMediaActionButtonsContainer: UIView = {
        let view = UIView()
        view.preservesSuperviewLayoutMargins = true
        view.layoutMargins.bottom = 0

        view.addSubview(buttonAddMedia)
        buttonAddMedia.autoPinHeightToSuperviewMargins()
        buttonAddMedia.layoutMarginsGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true

        view.addSubview(buttonViewOnce)
        buttonViewOnce.autoPinHeightToSuperviewMargins()
        buttonViewOnce.layoutMarginsGuide.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true

        return view
    }()
    let buttonAddMedia: UIButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-add-photos"), backgroundStyle: .blur)
    let buttonViewOnce: UIButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-view-once"), backgroundStyle: .blur)
    // Contains message input field and a button to finish editing.
    let attachmentTextToolbar: AttachmentTextToolbar
    weak var attachmentTextToolbarDelegate: AttachmentTextToolbarDelegate?
    // Shows previews of media object.
    let galleryRailView: GalleryRailView
    // Row of buttons at the bottom of the screen.
    private let mediaToolbar = MediaToolbar()

    private lazy var opaqueContentView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ attachmentTextToolbar, mediaToolbar ])
        stackView.axis = .vertical
        stackView.preservesSuperviewLayoutMargins = true
        return stackView
    }()

    private lazy var containerStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ opaqueContentView ])
        stackView.axis = .vertical
        stackView.preservesSuperviewLayoutMargins = true
        return stackView
    }()

    private var viewOnceTooltip: UIView?

    var isEditingMediaMessage: Bool {
        return attachmentTextToolbar.isEditingText
    }

    var isViewOnceOn: Bool = false {
        didSet {
            updateContents()
        }
    }

    var isMediaQualityHighEnabled: Bool {
        get {
            mediaToolbar.isMediaQualityHighEnabled
        }
        set {
            mediaToolbar.isMediaQualityHighEnabled = newValue
        }
    }

    private var currentAttachmentItem: AttachmentApprovalItem?

    override init(frame: CGRect) {
        configuration = Configuration()

        attachmentTextToolbar = AttachmentTextToolbar()
        attachmentTextToolbar.isViewOnceEnabled = isViewOnceOn

        galleryRailView = GalleryRailView()
        galleryRailView.scrollFocusMode = .keepWithinBounds
        galleryRailView.autoSetDimension(.height, toSize: 60)
        galleryRailView.alpha = 0 // match default value of `isMediaStripVisible`

        super.init(frame: frame)

        createContents()
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createContents() {
        self.backgroundColor = .clear
        self.layoutMargins.bottom = 0
        self.preservesSuperviewLayoutMargins = true

        attachmentTextToolbar.delegate = self

        addSubview(galleryRailView)
        galleryRailView.autoPinWidthToSuperview()
        galleryRailView.autoPinEdge(toSuperviewEdge: .top)

        addSubview(singleMediaActionButtonsContainer)
        singleMediaActionButtonsContainer.autoPinWidthToSuperview()
        singleMediaActionButtonsContainer.autoPinEdge(.bottom, to: .bottom, of: galleryRailView)

        // Use a background view that extends below the keyboard to avoid animation glitches.
        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(backgroundView)
        backgroundView.autoPinWidthToSuperview()
        backgroundView.autoPinEdge(.top, to: .bottom, of: galleryRailView)
        backgroundView.autoPinEdge(toSuperviewEdge: .bottom, withInset: -30)

        mediaToolbar.isMediaQualityHighEnabled = isMediaQualityHighEnabled

        addSubview(containerStackView)
        containerStackView.autoPinEdge(.top, to: .bottom, of: galleryRailView)
        containerStackView.autoPinWidthToSuperview()
        // We pin to the superview's _margin_.  Otherwise the notch breaks
        // the layout if you hide the keyboard in the simulator (or if the
        // user uses an external keyboard).
        containerStackView.autoPinEdge(toSuperviewMargin: .bottom)
    }

    private var supplementaryViewContainer: UIView?
    func set(supplementaryView: UIView?) {
        if let supplementaryViewContainer = supplementaryViewContainer {
            supplementaryViewContainer.removeFromSuperview()
            containerStackView.removeArrangedSubview(supplementaryViewContainer)
            self.supplementaryViewContainer = nil
        }
        guard let supplementaryView = supplementaryView else {
            return
        }

        let containerView = UIView()
        containerView.preservesSuperviewLayoutMargins = true
        containerView.addSubview(supplementaryView)
        supplementaryView.autoPinEdgesToSuperviewMargins()
        containerStackView.insertArrangedSubview(containerView, at: 0)
        self.supplementaryViewContainer = containerView
    }

    var opaqueAreaHeight: CGFloat { opaqueContentView.height }

    // MARK: 

    private func updateContents() {
        galleryRailView.alpha = configuration.isMediaStripVisible && !isEditingMediaMessage ? 1 : 0

        singleMediaActionButtonsContainer.isHidden = configuration.isMediaStripVisible || isEditingMediaMessage

        buttonAddMedia.isHidden = !configuration.isAddMoreVisible

        supplementaryViewContainer?.isHiddenInStackView = isEditingMediaMessage

        let viewOnceImageName = isViewOnceOn ? "media-editor-view-once" : "media-editor-view-infinite"
        buttonViewOnce.setImage(UIImage(named: viewOnceImageName), for: .normal)
        buttonViewOnce.isHidden = !configuration.canToggleViewOnce

        attachmentTextToolbar.isViewOnceEnabled = isViewOnceOn

        mediaToolbar.isHiddenInStackView = isEditingMediaMessage
        mediaToolbar.sendButton.setImage(UIImage(named: configuration.doneButtonAssetResourceName), for: .normal)
        mediaToolbar.mediaQualityButton.isHiddenInStackView = !configuration.canChangeMediaQuality
        mediaToolbar.saveMediaButton.isHiddenInStackView = !configuration.canSaveMedia
        mediaToolbar.availableTools = {
            guard let currentAttachmentItem = currentAttachmentItem else {
                return []
            }
            var options: MediaToolbar.AvailableTools = []
            if configuration.canSaveMedia {
                options.insert(.save)
            }
            switch currentAttachmentItem.type {
            case .image:
                options.insert(.pen)
                options.insert(.crop)

            default:
                break
            }
            return options
        }()

        updateFirstResponder()

        showViewOnceTooltipIfNecessary()

        layoutSubviews()
    }

    override func resignFirstResponder() -> Bool {
        if isEditingMediaMessage {
            return attachmentTextToolbar.textView.resignFirstResponder()
        } else {
            return super.resignFirstResponder()
        }
    }

    private func updateFirstResponder() {
        if isViewOnceOn {
            if isEditingMediaMessage {
                attachmentTextToolbar.textView.resignFirstResponder()
            }
        }
        // NOTE: We don't automatically make attachmentTextToolbar.textView
        // first responder;
    }

    func update(currentAttachmentItem: AttachmentApprovalItem, configuration: Configuration) {
        // De-bounce
        guard self.currentAttachmentItem != currentAttachmentItem || self.configuration != configuration else {
            updateFirstResponder()
            return
        }

        self.currentAttachmentItem = currentAttachmentItem
        self.configuration = configuration

        updateContents()
    }

    // MARK: 

    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    override var intrinsicContentSize: CGSize { .zero }

    public var hasFirstResponder: Bool {
        return (isFirstResponder || attachmentTextToolbar.textView.isFirstResponder)
    }
}

extension AttachmentApprovalToolbar: AttachmentTextToolbarDelegate {

    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        updateContents()
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidBeginEditing(attachmentTextToolbar)
    }

    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        updateContents()
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidEndEditing(attachmentTextToolbar)
    }

    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar) {
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidChange(attachmentTextToolbar)
    }
}

// MARK: - View Once Tooltip

extension AttachmentApprovalToolbar {

    // The tooltip lies outside this view's bounds, so we
    // need to special-case the hit testing so that it can
    // intercept touches within its bounds.
    @objc
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let viewOnceTooltip = self.viewOnceTooltip {
            let tooltipFrame = convert(viewOnceTooltip.bounds, from: viewOnceTooltip)
            if tooltipFrame.contains(point) {
                return true
            }
        }
        return super.point(inside: point, with: event)
    }

    private var shouldShowViewOnceTooltip: Bool {
        guard !configuration.isMediaStripVisible else {
            return false
        }
        guard !isViewOnceOn && configuration.canToggleViewOnce else {
            return false
        }
        guard !preferences.wasViewOnceTooltipShown() else {
            return false
        }
        return true
    }

    // Show the tooltip if a) it should be shown b) isn't already showing.
    private func showViewOnceTooltipIfNecessary() {
        guard shouldShowViewOnceTooltip else {
            return
        }
        guard nil == viewOnceTooltip else {
            // Already showing the tooltip.
            return
        }
        let tooltip = ViewOnceTooltip.present(fromView: self, widthReferenceView: self, tailReferenceView: buttonViewOnce) { [weak self] in
            self?.removeViewOnceTooltip()
        }
        viewOnceTooltip = tooltip

        DispatchQueue.global().async {
            self.preferences.setWasViewOnceTooltipShown()

            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) { [weak self] in
                self?.removeViewOnceTooltip()
            }
        }
    }

    private func removeViewOnceTooltip() {
        viewOnceTooltip?.removeFromSuperview()
        viewOnceTooltip = nil
    }

}

// MARK: - Bottom Row Buttons

extension AttachmentApprovalToolbar {

    var buttonSend: UIButton {
        mediaToolbar.sendButton
    }

    var buttonMediaQuality: UIButton {
        mediaToolbar.mediaQualityButton
    }

    var buttonSaveMedia: UIButton {
        mediaToolbar.saveMediaButton
    }

    var buttonPenTool: UIButton {
        mediaToolbar.penToolButton
    }

    var buttonCropTool: UIButton {
        mediaToolbar.cropToolButton
    }
}

private class MediaToolbar: UIView {

    struct AvailableTools: OptionSet {
        let rawValue: Int

        static let pen  = AvailableTools(rawValue: 1 << 0)
        static let crop = AvailableTools(rawValue: 1 << 1)
        static let save = AvailableTools(rawValue: 1 << 2)

        static let all: AvailableTools = [ .pen, .crop, .save ]
    }

    var availableTools: AvailableTools = .all {
        didSet {
            penToolButton.isHiddenInStackView = !availableTools.contains(.pen)
            cropToolButton.isHiddenInStackView = !availableTools.contains(.crop)
            saveMediaButton.isHiddenInStackView = !availableTools.contains(.save)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        layoutMargins.top = 2
        let bottomMargin: CGFloat = UIDevice.current.hasIPhoneXNotch ? 0 : -8

        let spacerView = UIView()
        let stackView = UIStackView(arrangedSubviews: [ penToolButton, cropToolButton, mediaQualityButton, saveMediaButton, spacerView, sendButton ])
        stackView.spacing = 4
        addSubview(stackView)
        stackView.autoPinLeadingToSuperviewMargin(withInset: -penToolButton.layoutMargins.leading)
        sendButton.layoutMarginsGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor).isActive = true
        stackView.autoPinTopToSuperviewMargin()
        stackView.autoPinEdge(.bottom, to: .bottom, of: self, withOffset: bottomMargin)

        stackView.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { button in
            button.setCompressionResistanceHigh()
        }
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    static private let buttonBackgroundColor = RoundMediaButton.defaultBackgroundColor
    let penToolButton: UIButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-tool-pen"), backgroundStyle: .solid(buttonBackgroundColor))
    let cropToolButton: UIButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-tool-crop"), backgroundStyle: .solid(buttonBackgroundColor))
    let mediaQualityButton: UIButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-quality"), backgroundStyle: .solid(buttonBackgroundColor))
    let saveMediaButton: UIButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-save"), backgroundStyle: .solid(buttonBackgroundColor))
    let sendButton: UIButton = {
        let button = RoundMediaButton(image: #imageLiteral(resourceName: "send-solid-24"), backgroundStyle: .solid(.ows_accentBlue))
        button.accessibilityLabel = MessageStrings.sendButton
        return button
    }()

    var isMediaQualityHighEnabled: Bool = false {
        didSet {
            let image = isMediaQualityHighEnabled ? #imageLiteral(resourceName: "media-editor-quality-high") : #imageLiteral(resourceName: "media-editor-quality")
            mediaQualityButton.setImage(image, for: .normal)
        }
    }
}
