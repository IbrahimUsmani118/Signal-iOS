# SignalCore

Core utilities and services for Signal iOS.

## Components

### SignalCoreUtility

A utility class providing common functionality for Signal iOS, including:

- **Logging**: Comprehensive logging utilities with support for different log levels and destinations
- **Version Information**: Retrieval of app version and build numbers
- **Device Information**: Methods to access device model and system version

## Usage

### Logging

The logging system supports multiple levels to appropriately categorize messages:

```swift
// Debug-level logging (development information)
SignalCoreUtility.logDebug("Initializing service")

// Info-level logging (operation success) 
SignalCoreUtility.logInfo("Message sent successfully")

// Warning-level logging (non-critical issues)
SignalCoreUtility.logWarning("Rate limit approaching")

// Error-level logging (recoverable errors)
SignalCoreUtility.logError("Failed to connect", error: connectionError)

// Critical-level logging (severe, potentially unrecoverable errors)
SignalCoreUtility.logCritical("Database corruption detected", error: dbError)
```

### Version Information

```swift
// Get the app's version
let version = SignalCoreUtility.appVersion()

// Get the build number
let build = SignalCoreUtility.appBuild()

// Get combined version and build
let versionString = SignalCoreUtility.appVersionAndBuild()
```

### Device Information

```swift
// Get device model
let model = SignalCoreUtility.deviceModel()

// Get iOS version
let iosVersion = SignalCoreUtility.systemVersion()
```

## Integration

SignalCoreUtility is designed to be imported and used throughout the Signal iOS codebase. It provides a consistent interface for common operations, reducing code duplication and ensuring standardized approaches to logging and system information access. 