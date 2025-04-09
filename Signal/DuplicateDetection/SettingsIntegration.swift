// DuplicateDetection/SettingsIntegration.swift

import Foundation
import SignalUI

class SettingsIntegration {
    static let shared = SettingsIntegration()
    
    func initialize() {
        // Add a swizzle to the PrivacySettingsViewController's updateTableContents method
        if let privacySettingsClass = NSClassFromString("PrivacySettingsViewController") as? NSObject.Type {
            let originalSelector = #selector(PrivacySettingsViewController.updateTableContents)
            let swizzledSelector = #selector(SettingsIntegration.dd_updateTableContents)
            
            guard let originalMethod = class_getInstanceMethod(privacySettingsClass, originalSelector),
                  let swizzledMethod = class_getInstanceMethod(SettingsIntegration.self, swizzledSelector) else {
                Logger.warn("Could not find PrivacySettingsViewController.updateTableContents to swizzle")
                return
            }
            
            method_exchangeImplementations(originalMethod, swizzledMethod)
            Logger.info("Successfully swizzled PrivacySettingsViewController.updateTableContents")
        }
    }
    
    @objc
    func dd_updateTableContents() {
        // Call original method first
        dd_updateTableContents()
        
        // Now add our duplicate detection item to the contents
        if let privacySettingsVC = self as? PrivacySettingsViewController {
            addDuplicateDetectionSettings(to: privacySettingsVC)
        }
    }
    
    func addDuplicateDetectionSettings(to privacySettingsVC: PrivacySettingsViewController) {
        guard let contents = privacySettingsVC.contents else {
            return
        }
        
        // Create a new section for our duplicate detection settings
        let duplicateDetectionSection = OWSTableSection()
        duplicateDetectionSection.headerTitle = "Duplicate Detection"
        duplicateDetectionSection.footerTitle = "Configure detection of duplicate images in conversations"
        
        // Add our duplicate detection item
        duplicateDetectionSection.add(OWSTableItem.disclosureItem(
            withText: "Duplicate Image Detection",
            accessibilityIdentifier: "settings.duplicate_detection",
            actionBlock: {
                let viewController = DuplicateDetectionViewController()
                privacySettingsVC.navigationController?.pushViewController(viewController, animated: true)
            }
        ))
        
        // Add our section to the contents
        // We want to insert it before the "Advanced" section, which is usually the last one
        if let advancedSectionIndex = contents.sections.firstIndex(where: { 
            $0.headerTitle == "Advanced" || 
            ($0.items.count == 1 && $0.items[0].itemType == .disclosureItem && 
             ($0.items[0] as? OWSTableItem)?.itemName == OWSLocalizedString(
                "SETTINGS_PRIVACY_ADVANCED_TITLE",
                comment: "Title for the advanced privacy settings"
             ))
        }) {
            contents.sections.insert(duplicateDetectionSection, at: advancedSectionIndex)
        } else {
            // If we can't find the advanced section, just add it to the end
            contents.add(duplicateDetectionSection)
        }
        
        // Update the view controller's contents
        privacySettingsVC.contents = contents
    }
}