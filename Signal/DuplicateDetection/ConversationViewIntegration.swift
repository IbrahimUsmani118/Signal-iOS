// DuplicateDetection/ConversationViewIntegration.swift
import Foundation
import SignalUI
import UIKit

extension ConversationViewController {
    @objc
    func addDuplicateIndicatorIfNeeded(forAttachment attachment: TSAttachment, inCell cell: UIView) {
        guard DuplicateDetectionManager.shared.isEnabled,
              let attachmentStream = attachment as? TSAttachmentStream,
              attachmentStream.isImage,
              let filePath = attachmentStream.originalFilePath else {
            return
        }
        
        // Check for duplicates
        DispatchQueue.global(qos: .userInitiated).async {
            let fileURL = URL(fileURLWithPath: filePath)
            guard let hash = ImageHasher.calculateImageHash(from: fileURL) else {
                return
            }
            
            // Check if this image is blocked
            let isBlocked = HashDatabase.getInstance().isSignatureBlocked(hash)
            
            // Get hash database
            let threshold = DuplicateDetectionManager.shared.getSimilarityThreshold()
            let similarImages = HashDatabase.getInstance().findSimilarImages(hash: hash, threshold: threshold)
            
            // If it's a duplicate (more than 1 because it matches itself) or blocked
            DispatchQueue.main.async { [weak self] in
                if isBlocked {
                    self?.showBlockedIndicator(inCell: cell)
                    self?.setupImageContextMenu(forCell: cell, hash: hash, isBlocked: true, fileURL: fileURL)
                } else if similarImages.count > 1 {
                    self?.showDuplicateIndicator(inCell: cell, count: similarImages.count - 1)
                    self?.setupImageContextMenu(forCell: cell, hash: hash, isBlocked: false, fileURL: fileURL)
                } else {
                    // Add context menu even if not a duplicate
                    self?.setupImageContextMenu(forCell: cell, hash: hash, isBlocked: false, fileURL: fileURL)
                }
            }
        }
    }
    
    private func showDuplicateIndicator(inCell cell: UIView, count: Int) {
        let indicator = UIView()
        indicator.backgroundColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 0.8)
        indicator.layer.cornerRadius = 12
        indicator.tag = 1001 // Use tag to find and remove if needed
        
        let label = UILabel()
        label.text = count > 1 ? "Duplicate (\(count))" : "Duplicate"
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 12)
        label.textAlignment = .center
        
        indicator.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: indicator.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: indicator.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: indicator.bottomAnchor, constant: -4)
        ])
        
        cell.addSubview(indicator)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
            indicator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8)
        ])
        
        // Add tap gesture to show options
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(duplicateIndicatorTapped(_:)))
        indicator.addGestureRecognizer(tapGesture)
        indicator.isUserInteractionEnabled = true
    }
    
    private func showBlockedIndicator(inCell cell: UIView) {
        let indicator = UIView()
        indicator.backgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.8)
        indicator.layer.cornerRadius = 12
        indicator.tag = 1002 // Use tag to find and remove if needed
        
        let label = UILabel()
        label.text = "Blocked"
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 12)
        label.textAlignment = .center
        
        indicator.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: indicator.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: indicator.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: indicator.bottomAnchor, constant: -4)
        ])
        
        cell.addSubview(indicator)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
            indicator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8)
        ])
        
        // Add tap gesture to show options
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(blockedIndicatorTapped(_:)))
        indicator.addGestureRecognizer(tapGesture)
        indicator.isUserInteractionEnabled = true
    }
    
    @objc
    private func duplicateIndicatorTapped(_ sender: UITapGestureRecognizer) {
        guard let indicator = sender.view,
              let cell = indicator.superview,
              let hash = cell.layer.value(forKey: "imageHash") as? String else {
            return
        }
        
        // Show actions for duplicate image
        let actionSheet = ActionSheetController(title: "Duplicate Image", message: "This image appears similar to others you've seen")
        
        actionSheet.addAction(ActionSheetAction(
            title: "Block This Image",
            style: .destructive
        ) { _ in
            DuplicateDetector.shared.blockImageHash(hash)
            // Replace the duplicate indicator with a blocked indicator
            indicator.removeFromSuperview()
            self.showBlockedIndicator(inCell: cell)
        })
        
        actionSheet.addAction(ActionSheetAction(
            title: "View Details",
            style: .default
        ) { _ in
            // Show details about the duplicate
            let detailVC = DuplicateDetailsViewController(imageHash: hash)
            self.present(detailVC, animated: true)
        })
        
        actionSheet.addAction(OWSActionSheets.cancelAction)
        
        presentActionSheet(actionSheet)
    }
    
    @objc
    private func blockedIndicatorTapped(_ sender: UITapGestureRecognizer) {
        guard let indicator = sender.view,
              let cell = indicator.superview,
              let hash = cell.layer.value(forKey: "imageHash") as? String else {
            return
        }
        
        // Show actions for blocked image
        let actionSheet = ActionSheetController(title: "Blocked Image", message: "This image has been blocked")
        
        actionSheet.addAction(ActionSheetAction(
            title: "Unblock This Image",
            style: .default
        ) { _ in
            DuplicateDetector.shared.unblockImageHash(hash)
            // Remove the blocked indicator
            indicator.removeFromSuperview()
            
            // Check if it's a duplicate and show that indicator instead
            DispatchQueue.global(qos: .userInitiated).async {
                let threshold = DuplicateDetectionManager.shared.getSimilarityThreshold()
                let similarImages = HashDatabase.getInstance().findSimilarImages(hash: hash, threshold: threshold)
                
                DispatchQueue.main.async { [weak self] in
                    // If it's still a duplicate, show the duplicate indicator
                    if similarImages.count > 1 {
                        self?.showDuplicateIndicator(inCell: cell, count: similarImages.count - 1)
                    }
                }
            }
        })
        
        actionSheet.addAction(OWSActionSheets.cancelAction)
        
        presentActionSheet(actionSheet)
    }
    
    private func setupImageContextMenu(forCell cell: UIView, hash: String, isBlocked: Bool, fileURL: URL) {
        // Store hash in the cell's layer for later access
        cell.layer.setValue(hash, forKey: "imageHash")
        
        // Set up context menu for the cell
        if #available(iOS 13.0, *) {
            let interaction = UIContextMenuInteraction(delegate: self)
            
            // Remove any existing interactions first
            cell.interactions.forEach { interaction in
                if interaction is UIContextMenuInteraction {
                    cell.removeInteraction(interaction)
                }
            }
            
            cell.addInteraction(interaction)
            
            // Store hash and URL for context menu
            cell.layer.setValue(hash, forKey: "contextMenuHash")
            cell.layer.setValue(isBlocked, forKey: "isBlocked")
            cell.layer.setValue(fileURL.path, forKey: "imageFilePath")
        }
    }
}

// MARK: - Context Menu Support (iOS 13+)
@available(iOS 13.0, *)
extension ConversationViewController: UIContextMenuInteractionDelegate {
    
    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let cell = interaction.view,
              let hash = cell.layer.value(forKey: "contextMenuHash") as? String,
              let isBlocked = cell.layer.value(forKey: "isBlocked") as? Bool,
              let filePath = cell.layer.value(forKey: "imageFilePath") as? String else {
            return nil
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        return UIContextMenuConfiguration(
            identifier: hash as NSString,
            previewProvider: nil
        ) { _ in
            // Create menu based on whether the image is blocked
            if isBlocked {
                return self.createBlockedImageContextMenu(hash: hash, cell: cell)
            } else {
                return self.createImageContextMenu(hash: hash, fileURL: fileURL, cell: cell)
            }
        }
    }
    
    private func createImageContextMenu(hash: String, fileURL: URL, cell: UIView) -> UIMenu {
        // Check if this is a duplicate
        let threshold = DuplicateDetectionManager.shared.getSimilarityThreshold()
        let similarImages = HashDatabase.getInstance().findSimilarImages(hash: hash, threshold: threshold)
        let isDuplicate = similarImages.count > 1
        
        var menuActions: [UIAction] = []
        
        // Block action
        let blockAction = UIAction(
            title: "Block This Image",
            image: UIImage(systemName: "hand.raised"),
            attributes: .destructive
        ) { [weak self] _ in
            DuplicateDetector.shared.blockImageHash(hash)
            
            // Replace any duplicate indicator with blocked indicator
            if let existingIndicator = cell.viewWithTag(1001) {
                existingIndicator.removeFromSuperview()
                self?.showBlockedIndicator(inCell: cell)
            } else if cell.viewWithTag(1002) == nil {
                // Show blocked indicator if none exists
                self?.showBlockedIndicator(inCell: cell)
            }
            
            // Provide feedback
            OWSActionSheets.showActionSheet(title: "Image Blocked", message: "This image has been added to your block list.")
        }
        menuActions.append(blockAction)
        
        // If it's a duplicate, add details action
        if isDuplicate {
            let detailsAction = UIAction(
                title: "View Duplicate Details",
                image: UIImage(systemName: "info.circle")
            ) { [weak self] _ in
                let detailVC = DuplicateDetailsViewController(imageHash: hash)
                self?.present(detailVC, animated: true)
            }
            menuActions.append(detailsAction)
        }
        
        return UIMenu(title: isDuplicate ? "Duplicate Image" : "Image Options", children: menuActions)
    }
    
    private func createBlockedImageContextMenu(hash: String, cell: UIView) -> UIMenu {
        let unblockAction = UIAction(
            title: "Unblock This Image",
            image: UIImage(systemName: "hand.raised.slash")
        ) { [weak self] _ in
            DuplicateDetector.shared.unblockImageHash(hash)
            
            // Remove blocked indicator
            if let blockedIndicator = cell.viewWithTag(1002) {
                blockedIndicator.removeFromSuperview()
                
                // Check if it's a duplicate and show that indicator instead
                DispatchQueue.global(qos: .userInitiated).async {
                    let threshold = DuplicateDetectionManager.shared.getSimilarityThreshold()
                    let similarImages = HashDatabase.getInstance().findSimilarImages(hash: hash, threshold: threshold)
                    
                    DispatchQueue.main.async {
                        // If it's still a duplicate, show the duplicate indicator
                        if similarImages.count > 1 {
                            self?.showDuplicateIndicator(inCell: cell, count: similarImages.count - 1)
                        }
                    }
                }
            }
            
            // Update cell's blocked status
            cell.layer.setValue(false, forKey: "isBlocked")
            
            // Provide feedback
            OWSActionSheets.showActionSheet(title: "Image Unblocked", message: "This image has been removed from your block list.")
        }
        
        return UIMenu(title: "Blocked Image", children: [unblockAction])
    }
}

// MARK: - DuplicateDetailsViewController

class DuplicateDetailsViewController: OWSViewController {
    private let imageHash: String
    private var similarImages: [ImageHashRecord] = []
    
    init(imageHash: String) {
        self.imageHash = imageHash
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Duplicate Image Details"
        
        view.backgroundColor = Theme.backgroundColor
        
        setupUI()
        loadData()
    }
    
    private func setupUI() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        let contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        
        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // Hash info section
        let hashInfoLabel = UILabel()
        hashInfoLabel.text = "Hash: \(imageHash)"
        hashInfoLabel.textColor = Theme.primaryTextColor
        hashInfoLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        hashInfoLabel.numberOfLines = 0
        hashInfoLabel.textAlignment = .center
        stackView.addArrangedSubview(hashInfoLabel)
        
        // Block button
        let blockButton = OWSButton()
        blockButton.setTitle("Block This Image", for: .normal)
        blockButton.setTitleColor(.white, for: .normal)
        blockButton.backgroundColor = .systemRed
        blockButton.layer.cornerRadius = 8
        blockButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        blockButton.addTarget(self, action: #selector(blockButtonTapped), for: .touchUpInside)
        stackView.addArrangedSubview(blockButton)
        
        // Spacer
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stackView.addArrangedSubview(spacer)
        
        // Loading indicator for occurrences
        let loadingIndicator = UIActivityIndicatorView(style: .medium)
        loadingIndicator.startAnimating()
        loadingIndicator.tag = 100
        stackView.addArrangedSubview(loadingIndicator)
        
        // Occurrences section will be populated in loadData()
    }
    
    private func loadData() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let threshold = DuplicateDetectionManager.shared.getSimilarityThreshold()
            self.similarImages = HashDatabase.getInstance().findSimilarImages(hash: self.imageHash, threshold: threshold)
            
            DispatchQueue.main.async {
                self.updateUI()
            }
        }
    }
    
    private func updateUI() {
        // Find the stack view
        guard let contentView = view.subviews.first(where: { $0 is UIScrollView }),
              let scrollView = contentView as? UIScrollView,
              let mainContentView = scrollView.subviews.first,
              let stackView = mainContentView.subviews.first(where: { $0 is UIStackView }) as? UIStackView else {
            return
        }
        
        // Remove loading indicator
        if let loadingIndicator = stackView.arrangedSubviews.first(where: { $0.tag == 100 }) {
            loadingIndicator.removeFromSuperview()
        }
        
        // Add occurrences section header
        let occurrencesHeaderLabel = UILabel()
        occurrencesHeaderLabel.text = "Occurrences (\(similarImages.count))"
        occurrencesHeaderLabel.textColor = Theme.primaryTextColor
        occurrencesHeaderLabel.font = UIFont.boldSystemFont(ofSize: 18)
        stackView.addArrangedSubview(occurrencesHeaderLabel)
        
        // Add each occurrence
        for (index, record) in similarImages.enumerated() {
            let occurrenceView = createOccurrenceView(record: record, index: index)
            stackView.addArrangedSubview(occurrenceView)
            
            // Add separator if not the last item
            if index < similarImages.count - 1 {
                let separator = UIView()
                separator.backgroundColor = Theme.secondaryBackgroundColor
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stackView.addArrangedSubview(separator)
            }
        }
    }
    
    private func createOccurrenceView(record: ImageHashRecord, index: Int) -> UIView {
        let container = UIView()
        container.backgroundColor = Theme.backgroundColor
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        
        container.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        
        // Conversation ID
        let conversationLabel = UILabel()
        conversationLabel.text = "Conversation: \(record.conversationId)"
        conversationLabel.textColor = Theme.primaryTextColor
        conversationLabel.font = UIFont.systemFont(ofSize: 16)
        stackView.addArrangedSubview(conversationLabel)
        
        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let dateLabel = UILabel()
        dateLabel.text = "Date: \(dateFormatter.string(from: record.timestamp))"
        dateLabel.textColor = Theme.secondaryTextAndIconColor
        dateLabel.font = UIFont.systemFont(ofSize: 14)
        stackView.addArrangedSubview(dateLabel)
        
        // Status (blocked or not)
        if record.blocked {
            let blockedLabel = UILabel()
            blockedLabel.text = "Status: Blocked"
            blockedLabel.textColor = .systemRed
            blockedLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            stackView.addArrangedSubview(blockedLabel)
        }
        
        return container
    }
    
    @objc private func blockButtonTapped() {
        DuplicateDetector.shared.blockImageHash(imageHash)
        
        // Show confirmation
        let alert = ActionSheetController(title: "Image Blocked", message: "This image has been added to your block list.")
        alert.addAction(ActionSheetAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        presentActionSheet(alert)
    }
}