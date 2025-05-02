# Signal iOS: Dependency Installation Report

This document provides an overview of the dependency installation process for the Signal iOS project, focusing on the required tools, key dependencies, potential issues, and resolution strategies.

## Overview

Signal iOS uses a combination of Ruby-based tooling, CocoaPods for dependency management, and custom scripts for fetching binaries. The primary command for setting up the development environment is `make dependencies`, which orchestrates several important setup tasks.

## Required Tools

### Ruby and Gems
- **Ruby 3.2.2** (installed and managed via rbenv)
- **Bundler** for managing Ruby gem dependencies
- **CocoaPods** for iOS dependency management
- **Fastlane** for automated builds and testing

### Xcode
- **Xcode 15.0+** (current development targets iOS 15.0+)
- Command Line Tools installed

### Other Requirements
- **Git** with submodule support
- **make** for running the dependency scripts

### System Dependencies

Some dependencies might require system-level tools to be installed.

- **rsync**:
  - **Why it's needed**: The `rsync` utility is used by CocoaPods during the installation process for certain pods, particularly those involving complex resource copying or build phase scripts.
  - **Specific Case**: The `LibMobileCoin` pod explicitly requires `rsync` to copy resources as part of its installation script within CocoaPods. Failure to have `rsync` available will cause the `pod install` step (run via `make dependencies`) to fail.
  - **Troubleshooting Error**: If you encounter an error message similar to `Unable to locate the executable \`rsync\`` during the `pod install` phase, it means `rsync` is not installed or not found in your system's PATH.
  - **Installation**:
    - **macOS (using Homebrew)**:
      ```bash
      brew install rsync
      ```
    - **Debian/Ubuntu (using apt)**:
      ```bash
      sudo apt-get update
      sudo apt-get install rsync
      ```
    - **Other Systems**: Use your system's package manager to install `rsync`.

## Dependency Installation Process

### What `make dependencies` Does

The `make dependencies` command (defined in the project's Makefile) performs three main tasks:

1. **Pod Setup** (`pod-setup`):
   - Cleans and resets the Pods directory
   - Runs `setup_private_pods` script to prepare any private pod dependencies
   - Updates Git submodules for the Pods directory

2. **Backup Tests Setup** (`backup-tests-setup`):
   - Updates the Git submodule for the Message Backup Tests

3. **Fetch RingRTC** (`fetch-ringrtc`):
   - Runs the script to fetch the RingRTC binary framework
   - Configures RingRTC for use with CocoaPods

This approach ensures all dependencies are consistently installed and configured across development environments.

## Key Dependencies

### Core Libraries
- **LibSignalClient** - For Signal protocol cryptography
- **SignalRingRTC** - For voice and video calling functionality
- **GRDB.swift/SQLCipher** - For encrypted database operations
- **SQLCipher** - For database encryption

### AWS Dependencies for Duplicate Content Detection
- **AWSCore** - Core AWS SDK functionality
- **AWSDynamoDB** - For DynamoDB operations to store and retrieve content hashes
- **AWSCognitoIdentityProvider** - For authentication with AWS services

The AWS dependencies are critical for the duplicate content detection system, which:
- Stores and retrieves content hashes in DynamoDB
- Uses Cognito for authentication
- Connects to a specific region (us-east-1 as configured in aws-config.json)
- Targets the "SignalContentHashes" DynamoDB table

### UI and Utilities
- **BonMot** - For attributed string handling
- **PureLayout** - For programmatic Auto Layout
- **lottie-ios** - For animations
- **LibMobileCoin** and **MobileCoin** - For payment functionality
- **YYImage** and **libwebp** - For image handling
- **blurhash** - For image placeholder blurring
- **SwiftProtobuf** - For protocol buffer support
- **Mantle** - For model object serialization (forked version)
- **libPhoneNumber-iOS** - For phone number formatting and validation (forked version)

## Common Issues and Troubleshooting

### CocoaPods Installation Issues
- **Problem**: Errors during pod installation like "Unable to find a specification for..."
- **Solution**: Run `bundle exec pod repo update` before `make dependencies`

### RingRTC Binary Issues
- **Problem**: Error messages about missing RingRTC prebuild directory
- **Solution**: Run `Pods/SignalRingRTC/bin/set-up-for-cocoapods` or `make fetch-ringrtc`

### AWS Configuration Problems
- **Problem**: AWS services cannot authenticate or find resources
- **Solution**: Check that aws-config.json has correct settings:
  - Verify the Cognito Identity Pool ID format (us-east-1:ee264a1b-9b89-4e4a-a346-9128da47af97)
  - Confirm DynamoDB table name (SignalContentHashes)
  - Ensure region is consistent (us-east-1)

### Ruby Version Mismatches
- **Problem**: Ruby gem errors due to version incompatibilities
- **Solution**: Ensure Ruby 3.2.2 is properly installed and activated via rbenv:
  ```
  rbenv install 3.2.2
  rbenv local 3.2.2
  bundle install
  ```

### Xcode Integration Issues
- **Problem**: "Framework not found" errors after updating dependencies
- **Solution**: Clean the build folder (⌘⇧K) and rebuild, or run:
  ```
  xcodebuild clean -workspace Signal.xcworkspace -scheme Signal
  ```

## Best Practices

1. **Always run `make dependencies` after pulling new changes** to ensure all dependencies are up to date.

2. **Isolate dependency issues** by examining specific parts of the installation process:
   - For CocoaPods issues: `make pod-setup`
   - For RingRTC issues: `make fetch-ringrtc`
   - For backup tests: `make backup-tests-setup`

3. **Check logs for specific errors** in case of failure. Most dependency scripts produce verbose output that can help diagnose issues.

4. **Use a clean environment** when having persistent issues:
   ```
   git clean -xfd
   git submodule foreach --recursive git clean -xfd
   make dependencies
   ```

5. **For AWS-related functionality**, verify your AWS credentials are properly configured for testing the duplicate content detection system.

## References

- Detailed build instructions are available in [BUILDING.md](BUILDING.md)
- CocoaPods dependencies are defined in [Podfile](Podfile)
- Dependency installation tasks are defined in [Makefile](Makefile)
- AWS configuration for duplicate content detection is in [aws-config.json](DuplicateContentDetection/aws-config.json)