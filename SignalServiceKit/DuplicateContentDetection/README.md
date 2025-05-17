# Duplicate Content Detection System

This module provides functionality to detect duplicate content (images, text) in the Signal app by using AWS services for image signature generation and DynamoDB for hash storage.

## Overview

The duplicate content detection system consists of the following components:

1. **AWSConfig**: Centralized configuration for all AWS services.
2. **AWSManager**: Main manager class for AWS-related functionality.
3. **S3Service**: Service for interacting with AWS S3 to store and retrieve files.
4. **ImageService**: Service for uploading images and retrieving image tags.
5. **DynamoDBService**: Service for storing and retrieving content hashes in DynamoDB.
6. **APIGatewayClient**: Client for making requests to the API Gateway.
7. **LambdaService**: Service for invoking AWS Lambda functions.
8. **DuplicateContentDetectionManager**: Main manager class for duplicate content detection.
9. **Logger**: Utility class for logging within the module.

## Usage

### Detecting Duplicate Images

```swift
import SignalServiceKit

// Get a reference to the manager
let manager = DuplicateContentDetectionManager.shared

// Check if an image is a duplicate
func checkImage(imageData: Data) async {
    let result = await manager.checkForDuplicateImage(imageData: imageData)
    
    switch result {
    case .unique:
        print("Image is unique and has been added to the detection system")
        
    case .duplicate(let tag):
        print("Image is a duplicate with tag: \(tag)")
        
    case .error(let error):
        print("Error checking image: \(error)")
    }
}
```

### Detecting Duplicate Text

```swift
import SignalServiceKit

// Get a reference to the manager
let manager = DuplicateContentDetectionManager.shared

// Check if text is a duplicate
func checkText(text: String) async {
    let result = await manager.checkForDuplicateText(text)
    
    switch result {
    case .unique:
        print("Text is unique and has been added to the detection system")
        
    case .duplicate(let hash):
        print("Text is a duplicate with hash: \(hash)")
        
    case .error(let error):
        print("Error checking text: \(error)")
    }
}
```

### Blocking Images

```swift
import SignalServiceKit

// Get a reference to the manager
let manager = DuplicateContentDetectionManager.shared

// Block an image
func blockImage(imageData: Data) async {
    let success = await manager.blockImage(imageData: imageData)
    
    if success {
        print("Image has been successfully blocked")
    } else {
        print("Failed to block image")
    }
}
```

## Testing

### Running Unit Tests

Execute the script to run the unit tests:

```bash
./SignalServiceKit/DuplicateContentDetection/Tests/run_tests.sh
```

### Manual Testing UI

To add the test UI to an existing view controller:

```swift
import SignalServiceKit

class YourViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add a test button
        DuplicateContentDetectionTestApp.addTestButton(to: self)
    }
}
```

Alternatively, you can directly present the test UI:

```swift
import SignalServiceKit

// In any view controller
func showTestUI() {
    DuplicateContentDetectionTestApp.showTestUI(from: self)
}
```

## SwiftUI Integration

If using SwiftUI, you can integrate the test UI using:

```swift
import SignalServiceKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        DuplicateContentDetectionTestView()
    }
}
```

## Configuration

The system uses `AWSConfig` for all configuration settings. Update this file to change AWS credentials, endpoints, etc.

## Architecture

The system follows a service-oriented architecture:

1. User-facing components (e.g., DuplicateContentDetectionManager) provide a simple API.
2. Service components (e.g., ImageService, DynamoDBService) handle specific AWS interactions.
3. AWS configuration is centralized in AWSConfig.
4. All operations are asynchronous using Swift's async/await pattern.

## Error Handling

The system uses specific error types for each service:
- `ImageServiceError`
- `DynamoDBServiceError`
- `LambdaServiceError`
- `APIGatewayError`
- `DetectionError`

These are encapsulated in the `DetectionResult` enum for user-facing APIs.

## Logging

The system uses a custom Logger class that wraps CocoaLumberjack for logging:

```swift
// Configure logging
Logger.configure()

// Log messages
Logger.info("Information message")
Logger.error("Error message")
Logger.debug("Debug message")
```

## AWS Credentials

For security reasons, AWS credentials should be handled with care:
- In production, use AWS Cognito or a similar service for authentication.
- Never hardcode AWS credentials in the app.
- The test implementation uses placeholder values in `AWSConfig`.

## Dependencies

- CocoaLumberjack for logging
- Swift 5.5+ for async/await support
- iOS 13.0+ (for SwiftUI integration) 