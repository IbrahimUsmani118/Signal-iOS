import UIKit
import SignalUI

class DuplicateDetectionViewController: OWSTableViewController2 {
    private let manager = DuplicateDetectionManager.shared
    
    private let enableSwitch = UISwitch()
    private let thresholdSlider = UISlider()
    private let thresholdValueLabel = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Duplicate Image Detection"
        
        // Configure controls
        enableSwitch.isOn = manager.isEnabled
        enableSwitch.addTarget(self, action: #selector(enableSwitchChanged), for: .valueChanged)
        
        thresholdSlider.minimumValue = 5
        thresholdSlider.maximumValue = 20
        thresholdSlider.value = Float(manager.getSimilarityThreshold())
        thresholdSlider.addTarget(self, action: #selector(thresholdSliderChanged), for: .valueChanged)
        
        thresholdValueLabel.text = "\(Int(thresholdSlider.value))"
        thresholdValueLabel.textAlignment = .right
        
        updateTableContents()
    }
    
    func updateTableContents() {
        let contents = OWSTableContents()
        
        // Settings section
        let settingsSection = OWSTableSection()
        settingsSection.headerTitle = "Settings"
        
        // Enable/disable setting
        let enableItem = OWSTableItem.switch(withText: "Enable Duplicate Detection", 
                                           isOn: { [weak self] in
                                               self?.manager.isEnabled ?? false
                                           },
                                           target: self,
                                           selector: #selector(enableSwitchChanged))
        settingsSection.add(enableItem)
        
        // Sensitivity slider
        let sensitivityItem = OWSTableItem.item(withCustomCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            
            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.spacing = 8
            stackView.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
            stackView.isLayoutMarginsRelativeArrangement = true
            
            let titleLabel = UILabel()
            titleLabel.text = "Sensitivity"
            titleLabel.font = UIFont.dynamicTypeBodyClamped
            
            let subtitleLabel = UILabel()
            subtitleLabel.text = "Lower values detect more duplicates but may increase false positives"
            subtitleLabel.font = UIFont.dynamicTypeCaption1Clamped
            subtitleLabel.textColor = Theme.secondaryTextAndIconColor
            
            let sliderStack = UIStackView()
            sliderStack.axis = .horizontal
            sliderStack.spacing = 10
            sliderStack.alignment = .center
            
            sliderStack.addArrangedSubview(self.thresholdSlider)
            sliderStack.addArrangedSubview(self.thresholdValueLabel)
            
            self.thresholdValueLabel.setContentHuggingPriority(.required, for: .horizontal)
            self.thresholdValueLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true
            
            stackView.addArrangedSubview(titleLabel)
            stackView.addArrangedSubview(subtitleLabel)
            stackView.addArrangedSubview(sliderStack)
            
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()
            
            return cell
        })
        settingsSection.add(sensitivityItem)
        
        // Storage duration
        let storageDurations = [7, 14, 30, 60, 90, 180, 365]
        let storageDurationTexts = ["1 week", "2 weeks", "1 month", "2 months", "3 months", "6 months", "1 year"]
        
        let currentDuration = manager.getStorageDuration()
        let currentDurationIndex = storageDurations.firstIndex(of: currentDuration) ?? 2 // Default to 30 days
        
        let storageDurationItem = OWSTableItem.disclosureItem(withText: "Storage Duration",
                                                            detailText: storageDurationTexts[currentDurationIndex],
                                                            actionBlock: { [weak self] in
            self?.showStorageDurationPicker()
        })
        settingsSection.add(storageDurationItem)
        
        // Actions section
        let actionsSection = OWSTableSection()
        actionsSection.headerTitle = "Actions"
        
        let clearAllItem = OWSTableItem.item(withText: "Clear All Stored Hashes",
                                           actionBlock: { [weak self] in
            self?.promptToClearAllHashes()
        })
        
        actionsSection.add(clearAllItem)
        
        // Add sections to contents
        contents.addSection(settingsSection)
        contents.addSection(actionsSection)
        
        self.contents = contents
    }
    
    // MARK: - Actions
    
    @objc private func enableSwitchChanged() {
        manager.isEnabled = enableSwitch.isOn
        updateTableContents()
    }
    
    @objc private func thresholdSliderChanged() {
        let value = Int(thresholdSlider.value)
        thresholdValueLabel.text = "\(value)"
        manager.setSimilarityThreshold(value)
    }
    
    private func showStorageDurationPicker() {
        let storageDurations = [7, 14, 30, 60, 90, 180, 365]
        let storageDurationTexts = ["1 week", "2 weeks", "1 month", "2 months", "3 months", "6 months", "1 year"]
        
        let currentDuration = manager.getStorageDuration()
        let currentIndex = storageDurations.firstIndex(of: currentDuration) ?? 2 // Default to 30 days
        
        let actionSheet = ActionSheetController(title: "Storage Duration", message: "How long to remember image hashes")
        
        for (index, text) in storageDurationTexts.enumerated() {
            let action = ActionSheetAction(title: text, style: .default) { [weak self] _ in
                self?.manager.setStorageDuration(storageDurations[index])
                self?.updateTableContents()
            }
            
            // Add checkmark to current selection
            if index == currentIndex {
                action.trailingIcon = .check
            }
            
            actionSheet.addAction(action)
        }
        
        actionSheet.addAction(OWSActionSheets.cancelAction)
        
        presentActionSheet(actionSheet)
    }
    
    private func promptToClearAllHashes() {
        let actionSheet = ActionSheetController(title: "Clear All Hashes", 
                                              message: "Are you sure you want to delete all stored image hashes?")
        
        let deleteAction = ActionSheetAction(title: "Clear All", style: .destructive) { _ in
            DuplicateDetector.shared.clearAllHashes()
        }
        
        actionSheet.addAction(deleteAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)
        
        presentActionSheet(actionSheet)
    }
}