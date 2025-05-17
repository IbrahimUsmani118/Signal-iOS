# Integrating Duplicate Content Detection with Signal-iOS

This document provides instructions on how to integrate the duplicate content detection system with the main Signal-iOS application.

## Step 1: Initialize the System

The duplicate content detection system should be initialized during application startup. Add the following code to `AppDelegate.swift`:

```swift
import SignalServiceKit

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // ... existing code ...
    
    // Initialize duplicate content detection logging
    Logger.configure()
    
    // ... rest of initialization ...
    
    return true
}
```

## Step 2: Add Detection to Message Sending

To check for duplicate content when sending messages, modify the message sending flow to include a check:

```swift
import SignalServiceKit

// Example integration with message sending
func sendMessage(text: String, attachments: [Data], thread: TSThread) async {
    let manager = DuplicateContentDetectionManager.shared
    
    // Check for duplicate text if needed
    if !text.isEmpty {
        let textResult = await manager.checkForDuplicateText(text)
        
        if case .duplicate(_) = textResult {
            // Display a warning to the user about duplicate content
            showDuplicateContentWarning(type: "text")
        }
    }
    
    // Check for duplicate images
    for attachmentData in attachments {
        let imageResult = await manager.checkForDuplicateImage(imageData: attachmentData)
        
        if case .duplicate(_) = imageResult {
            // Display a warning to the user about duplicate content
            showDuplicateContentWarning(type: "image")
            break
        }
    }
    
    // Continue with message sending
    // ...
}

func showDuplicateContentWarning(type: String) {
    // Show an alert to the user
    let alert = UIAlertController(
        title: "Duplicate Content Detected",
        message: "This \(type) appears to be a duplicate of content that has been shared before. Do you still want to send it?",
        preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "Send Anyway", style: .default))
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    
    // Present the alert
    window?.rootViewController?.present(alert, animated: true)
}
```

## Step 3: Add Detection to Media Viewing

To block known harmful images, integrate with the media viewing flow:

```swift
import SignalServiceKit

// Example integration with media viewing
func displayMedia(attachment: TSAttachment) async {
    guard let attachmentData = attachment.data else {
        // Handle missing data
        return
    }
    
    let manager = DuplicateContentDetectionManager.shared
    let result = await manager.checkForDuplicateImage(imageData: attachmentData)
    
    if case .duplicate(let tag) = result {
        // Check if this is a blocked image
        let isBlocked = await isBlockedImage(tag: tag)
        
        if isBlocked {
            // Show warning and blur image
            showBlockedContentWarning()
            displayBlurredImage(attachmentData)
            return
        }
    }
    
    // Display the media normally
    displayImage(attachmentData)
}

func isBlockedImage(tag: String) async -> Bool {
    // Check in a global blocklist or with the server
    do {
        return try await GlobalSignatureService.shared.checkTagExists(tag)
    } catch {
        // Handle errors
        Logger.error("Failed to check if image is blocked: \(error)")
        return false
    }
}
```

## Step 4: Add Admin Tools for Content Blocking

For admin users or moderators, add functionality to block harmful content:

```swift
import SignalServiceKit

// Example integration with admin tools
func blockHarmfulContent(imageData: Data) async {
    let manager = DuplicateContentDetectionManager.shared
    let success = await manager.blockImage(imageData: imageData)
    
    if success {
        // Show success message
        showAlert(title: "Content Blocked", message: "The image has been added to the block list.")
    } else {
        // Show error message
        showAlert(title: "Error", message: "Failed to block the image. Please try again.")
    }
}
```

## Step 5: Add the Test UI (Development Only)

During development and testing, you can add the test UI to any view controller:

```swift
import SignalServiceKit

class DebugViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add a test button
        #if DEBUG
        DuplicateContentDetectionTestApp.addTestButton(to: self)
        #endif
    }
}
```

## Step 6: Update AWS Credentials

Update the AWS credentials in a secure way rather than hardcoding them:

1. Create a secure storage mechanism for AWS credentials.
2. Modify `AWSConfig.swift` to use this secure storage.
3. Consider using AWS Cognito for identity management and authentication.

Example of a more secure approach:

```swift
public struct AWSConfig {
    // ... existing code ...
    
    // Use a secure keychain storage instead of hardcoded values
    public static var accessKeyId: String {
        return KeychainStorage.getString(forKey: "aws_access_key_id") ?? ""
    }
    
    public static var secretAccessKey: String {
        return KeychainStorage.getString(forKey: "aws_secret_access_key") ?? ""
    }
    
    public static var sessionToken: String {
        return KeychainStorage.getString(forKey: "aws_session_token") ?? ""
    }
    
    // ... rest of the code ...
}
```

## Step 7: Error Handling and Offline Support

Enhance the duplicate content detection system with proper error handling and offline support:

```swift
import SignalServiceKit

extension DuplicateContentDetectionManager {
    // Improved version with offline support
    func checkForDuplicateImageWithOfflineSupport(imageData: Data) async -> DetectionResult {
        // Check network connectivity
        guard NetworkManager.shared.isOnline else {
            // If offline, perform local check only
            return await performLocalCheck(imageData: imageData)
        }
        
        // If online, perform full check
        return await checkForDuplicateImage(imageData: imageData)
    }
    
    private func performLocalCheck(imageData: Data) async -> DetectionResult {
        // Perform a local-only check using cached data
        // This is a simplified implementation
        return .unique
    }
}
```

## Step 8: Performance Optimization

Optimize the system for performance:

1. Add caching for recently checked content
2. Reduce image size before sending for tagging
3. Add background processing for non-urgent checks

## Step 9: Testing

Ensure you run tests after integration:

```bash
./SignalServiceKit/DuplicateContentDetection/Tests/run_tests.sh
```

## Step 10: Monitoring and Logging

Set up proper monitoring and logging to track the system's performance:

```swift
// Configure logging levels based on the environment
if isProduction {
    Logger.currentLogLevel = .info
} else {
    Logger.currentLogLevel = .debug
}
```

## Further Considerations

1. **Privacy**: Ensure that the system respects user privacy and doesn't unnecessarily store or transmit user data.
2. **Resource Usage**: Monitor the system's impact on battery and network usage.
3. **Documentation**: Keep the documentation updated as the system evolves.
4. **User Experience**: Consider how to communicate duplicate content detection to users without disrupting their experience. 