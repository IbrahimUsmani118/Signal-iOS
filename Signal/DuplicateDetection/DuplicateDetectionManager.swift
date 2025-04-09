import Foundation
import SignalServiceKit
/// Manages duplicate detection settings
class DuplicateDetectionManager {
    static let shared = DuplicateDetectionManager()
    
    private let userDefaults = UserDefaults.standard
    
    // Default values
    private let defaultSimilarityThreshold = 12
    private let defaultStorageDuration = 30 // days
    
    // Keys for UserDefaults
    private let enabledKey = "duplicateDetection.enabled"
    private let thresholdKey = "duplicateDetection.similarityThreshold"
    private let storageDurationKey = "duplicateDetection.storageDuration"
    
    private init() {
        // Initialize default values if not set
        if userDefaults.object(forKey: enabledKey) == nil {
            userDefaults.set(true, forKey: enabledKey)
        }
        
        if userDefaults.object(forKey: thresholdKey) == nil {
            userDefaults.set(defaultSimilarityThreshold, forKey: thresholdKey)
        }
        
        if userDefaults.object(forKey: storageDurationKey) == nil {
            userDefaults.set(defaultStorageDuration, forKey: storageDurationKey)
        }
    }
    
    /// Check if duplicate detection is enabled
    var isEnabled: Bool {
        get { userDefaults.bool(forKey: enabledKey) }
        set { userDefaults.set(newValue, forKey: enabledKey) }
    }
    
    /// Get current similarity threshold (lower = more sensitive)
    func getSimilarityThreshold() -> Int {
        return userDefaults.integer(forKey: thresholdKey)
    }
    
    /// Set similarity threshold
    func setSimilarityThreshold(_ threshold: Int) {
        userDefaults.set(threshold, forKey: thresholdKey)
    }
    
    /// Get storage duration in days
    func getStorageDuration() -> Int {
        return userDefaults.integer(forKey: storageDurationKey)
    }
    
    /// Set storage duration in days
    func setStorageDuration(_ days: Int) {
        userDefaults.set(days, forKey: storageDurationKey)
    }
    
    /// Initialize settings and schedule maintenance
    func initialize() {
        // Schedule periodic maintenance
        schedulePeriodicMaintenance()
    }
    
    /// Schedule periodic maintenance
    private func schedulePeriodicMaintenance() {
        // Run maintenance once a day
        let timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            guard let self = self, self.isEnabled else { return }
            DuplicateDetector.shared.performMaintenance()
        }
        timer.tolerance = 60 * 60 // 1 hour tolerance
        RunLoop.main.add(timer, forMode: .common)
    }

    // In DuplicateDetectionManager.swift

public func setupDuplicateDetection() {
    // Initialize components
    self.initialize()
    
    // Start the attachment processor
    AttachmentProcessor.shared.setup()
    
    // Install our download hook
    AttachmentDownloadHook.shared.install()
    
    // Add observer for duplicates
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleDuplicateImageDetected(_:)),
        name: DuplicateDetector.duplicateImageDetectedNotification,
        object: nil
    )
    
    Logger.debug("Duplicate detection system initialized")
}

@objc
private func handleDuplicateImageDetected(_ notification: Notification) {
    guard isEnabled,
          let userInfo = notification.userInfo,
          let count = userInfo["count"] as? Int,
          let conversationId = userInfo["conversationId"] as? String else {
        return
    }
    
    // Log the detection
    Logger.info("Duplicate image detected: \(count) similar images in conversation \(conversationId)")
}
}