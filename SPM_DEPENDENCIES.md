# SPM_DEPENDENCIES.md - Swift Package Manager Dependencies Guide

## Overview: Using CocoaPods and SPM in Signal iOS

The Signal iOS project uses a hybrid dependency management approach, leveraging both CocoaPods and Swift Package Manager (SPM) to manage different types of dependencies. This document explains the reasoning, responsibilities, and workflow for this dual approach.

### Why Both Systems?

1.  **Historical Context**: The project initially used CocoaPods exclusively. SPM is being gradually adopted as it matures and offers enhanced integration with Xcode.

2.  **Dependency Compatibility**: Some dependencies (including forks and binaries) work best with CocoaPods due to specialized build settings, while Swift-native libraries often work better with SPM.

3.  **Transition Strategy**: The dual approach allows for a gradual, low-risk migration from CocoaPods to SPM over time without disrupting development workflows.

4.  **Platform Support**: SPM offers superior support for Swift-based, multi-platform libraries, while CocoaPods provides robust support for Objective-C libraries and complex build requirements.

## Dependency Responsibilities

### Managed by CocoaPods:

-   **Core Signal Libraries**: LibSignalClient, SignalRingRTC (complex native libraries with complex build requirements)
-   **Database Components**: GRDB.swift/SQLCipher, SQLCipher (encryption requirements)
-   **Forked Libraries**: Mantle, libPhoneNumber-iOS, YYImage (Signal-specific forks)
-   **UI Components**: BonMot, PureLayout, lottie-ios (established Objective-C/Swift libraries)
-   **Crypto & Payments**: LibMobileCoin, MobileCoin (complex cryptography libraries)
-   **Other Project-Specific Pods**: Any pods not explicitly managed by SPM for a given target.

### Managed by SPM:

-   **Swift Utilities**: swift-argument-parser, swift-log, swift-algorithms, swift-collections, swift-numerics, swift-atomics
-   **Cryptography Extensions**: swift-crypto (supplementary to core crypto)
-   **Concurrency Tools**: swift-async-algorithms
-   **AWS SDK (via SPM)**: aws-sdk-ios-spm (Exclusively manages AWS dependencies for SPM-defined targets like `DuplicateContentDetection`).
-   **Other Swift-native Libraries**: Modern Swift-only dependencies

## Details on Key SPM Dependencies

### swift-log (Logging)
-   **Purpose**: Provides a common logging API used throughout the Swift codebase, allowing for flexible backend integration (e.g., logging to console, files, or custom destinations). Used by `MyTool` and potentially other SPM modules.
-   **Version**: Pinned to an exact version (`1.6.3`) for stability.

### AWS SDK (aws-sdk-ios-spm)
-   **Purpose**: Provides the necessary modules to interact with AWS services for the Duplicate Content Detection (DCD) system. **This SPM package is now the exclusive source for AWS dependencies for modules defined in `Package.swift` (e.g., `DuplicateContentDetection`, `SignalCore`, `DuplicateContentDetectionTests`).**
-   **Modules Used by DCD Target**:
    -   `AWSCore`: Core functionalities, credentials provider.
    -   `AWSCognitoIdentity`: Used for obtaining temporary AWS credentials via Cognito Identity Pools.
    -   `AWSDynamoDB`: Interacting with the DynamoDB table (`SignalContentHashes`) via the backend API.
    -   `AWSAPIGateway`: Making requests to the API Gateway endpoints that manage hash operations.
    -   `AWSS3`: Used by `S3toDynamoDBImporter` and related tests.
    -   `AWSLambda`: Used for invoking Lambda functions (via service/importer) or in tests.
    -   *Note: Only modules directly required by the SPM target's source code are listed as dependencies in `Package.swift`.*
-   **Version**: Pinned to an exact version (`2.40.1`) to ensure consistency and prevent unexpected breaking changes from AWS SDK updates. This matches the version specified in `swift-packages.json`.
-   **Conflict Resolution**: Previously, AWS dependencies were present in both CocoaPods (`Podfile`) and SPM (`Package.swift`), causing potential conflicts. **This has been resolved by relying solely on this SPM package for AWS dependencies within SPM-managed targets. Corresponding AWS entries should be removed from the `Podfile` (see Action 33-6).** Developers should **not** add AWS pods back to the `Podfile` for these modules.

## Adding New Dependencies

### Adding a CocoaPods Dependency:

1.  **Edit the Podfile**:
    ```ruby
    pod 'DependencyName', '~> x.y.z'
    ```

2.  **Update Project**:
    ```bash
    bundle exec pod install
    # OR
    make dependencies
    ```

3.  **Target-Specific Dependencies**:
    To add a dependency only to specific targets, place it within the appropriate target block:
    ```ruby
    target 'Signal' do
      pod 'DependencyName'
    end
    ```

4.  **Using a Fork**:
    ```ruby
    pod 'DependencyName', git: 'https://github.com/signalapp/DependencyName', branch: 'signal-master'
    ```

### Adding an SPM Dependency:

1.  **Add to root Package.swift**:
    Update the `dependencies` array:
    ```swift
    dependencies: [
        .package(url: "https://github.com/example/package.git", exact: "1.0.0")
    ],
    ```
    Update the relevant target's `dependencies`:
    ```swift
    targets: [
        .target(
            name: "YourTarget",
            dependencies: [
                .product(name: "ProductName", package: "package"),
            ]
        ),
    ]
    ```

2.  **Add Pin to Signal.xcworkspace/swift-packages.json**:
    Add an entry to the `pins` array, ensuring the `revision` and `version` match the intended commit/tag:
    ```json
    {
      "identity": "package-name",
      "kind": "remote",
      "location": "https://github.com/example/package.git",
      "state": {
        "revision": "abcdef1234567890abcdef1234567890abcdef12", // The exact commit hash
        "version": "1.0.0" // The semantic version tag
      },
      "description": "Brief description of the package's purpose."
    }
    ```
    *Note: The `swift-packages.json` file serves as documentation and a backup reference for pinned versions, complementing the `Package.resolved` file which Xcode manages.*

3.  **Resolve in Xcode**:
    Xcode should automatically detect changes to `Package.swift` and resolve dependencies. If not:
    -   Go to File > Packages > Resolve Package Versions.
    -   Alternatively, File > Packages > Reset Package Caches might be needed.

4.  **In Xcode UI (Alternative)**: You can also add SPM packages directly in Xcode:
    -   Select the Signal project in the Navigator.
    -   Go to the "Package Dependencies" tab.
    -   Click "+" to add a package.
    -   Enter the repository URL and select version requirements.
    -   Choose which targets should use the package.
    -   Ensure the root `Package.swift` and `swift-packages.json` are manually updated to reflect changes made via the UI for consistency and tracking.

## Troubleshooting Dependency Conflicts

### CocoaPods Issues:

1.  **Versioning Conflicts**:
    -   Check your `Podfile.lock` for dependency version conflicts.
    -   Try `bundle exec pod update [PodName]` to update specific dependencies.
    -   Use `bundle exec pod install --repo-update` to refresh the spec repositories.

2.  **Build Errors**:
    -   Check if the pod's minimum iOS version is compatible with the project (`iOS 15.0`).
    -   Review `Podfile` `post_install` hooks that modify build settings.

3.  **Missing Dependencies**:
    -   Run `make dependencies` instead of just `pod install` to ensure all Signal-specific setup (like fetching RingRTC) is performed.
    -   Check if any system-level dependencies (like `rsync`) are missing (`brew install rsync` or `sudo apt-get install rsync`).

4.  **CocoaPods Cleanup**:
    ```bash
    rm -rf Pods
    rm Podfile.lock
    rm -rf ~/Library/Caches/CocoaPods
    rm -rf ~/Library/Developer/Xcode/DerivedData
    bundle exec pod install
    # OR
    make dependencies
    ```

### SPM Issues:

1.  **Package Resolution Failures**:
    -   In Xcode: File > Packages > Reset Package Caches.
    -   In Xcode: File > Packages > Resolve Package Versions.
    -   Verify `Package.swift` and `swift-packages.json` are consistent.
    -   Command line (from project root): `swift package resolve`.

2.  **Version Compatibility**:
    -   Ensure Swift tools version in `Package.swift` (currently `6.0`) is compatible with your Xcode version.
    -   Check for conflicting dependencies that might require incompatible versions of shared libraries (Xcode usually flags this).

3.  **Build Errors**:
    -   Clean the build folder (Cmd+Shift+K).
    -   Check the `Package.resolved` file (in `Signal.xcworkspace/xcshareddata/swiftpm/`) for the versions Xcode actually resolved.
    -   Manually delete the `DerivedData` folder: `rm -rf ~/Library/Developer/Xcode/DerivedData`.
    -   Manually delete the project's `.build` directory (if present) and resolve packages again.

4.  **Mixing SPM and CocoaPods**:
    -   Ensure a dependency is not declared in both `Package.swift` and `Podfile` unless explicitly intended and managed carefully during a migration phase.
    -   **AWS SDK Conflict (Resolved)**: The previous conflict caused by having AWS SDK dependencies in both systems has been addressed. AWS dependencies for modules like `DuplicateContentDetection` are now managed *exclusively* via the `aws-sdk-ios-spm` package in `Package.swift`. **Do not add `AWSCore` or related AWS pods back to the `Podfile` for these SPM-managed targets.** Ensure the `Podfile` has been updated accordingly (see Action 33-6).
    -   Be aware of potential symbol conflicts if the *same underlying library* (especially C libraries) is brought in via both systems with different versions.
    -   **Submodule Initialization**: Remember that some core dependencies (like `libsignal`) are managed via Git submodules, not SPM or CocoaPods. Always ensure submodules are correctly initialized and updated (`git submodule update --init --recursive`) as per `BUILDING.md`.

## Best Practices

### Versioning Strategy

-   **SPM**: We primarily use `.exact("x.y.z")` version constraints in `Package.swift` and corresponding explicit versions in `swift-packages.xcworkspace/swift-packages.json`. This provides maximum stability by ensuring that `swift package resolve` or Xcode always fetches the exact same version, preventing unexpected updates or potential build breaks caused by minor or patch releases of dependencies. This is crucial for a project like Signal that requires high reliability.
-   **CocoaPods**: Similar stability is achieved through the `Podfile.lock` file, which records the exact versions used. Pessimistic operators (`~> x.y.z`) are often used in the `Podfile` to allow patch updates while locking major/minor versions.

1.  **Pin Versions**:
    -   For CocoaPods, use explicit versions (`'x.y.z'`) or pessimistic versioning (`'~> x.y.z'`).
    -   For SPM, use `.exact("x.y.z")` in `Package.swift` and ensure the `revision` and `version` in `swift-packages.json` match the exact intended release.

2.  **Limit Third-Party Code**:
    -   Evaluate if new dependencies are truly necessary or if functionality can be implemented directly.
    -   Prefer smaller, single-purpose libraries over large multi-functional ones if possible.

3.  **Documentation**:
    -   Document why each dependency is needed, especially less common ones.
    -   Note any specific configuration requirements or forks in comments (`Podfile`, `Package.swift`, `swift-packages.json`).

4.  **Testing**:
    -   Thoroughly test app functionality after adding or updating dependencies.
    -   Run unit and integration tests.

5.  **Security**:
    -   Regularly update dependencies using `bundle exec pod update` or by updating versions in `Package.swift`/`swift-packages.json` and resolving.
    -   Review the security implications and track record of new dependencies.

6.  **Separation of Concerns**:
    -   Use SPM primarily for Swift-native utilities and libraries where possible.
    -   Continue using CocoaPods for complex native libraries, forks, or dependencies requiring specific `post_install` configurations until migration is feasible.

## Updating Dependencies

Regularly updating dependencies is important for security and accessing new features.

### Updating CocoaPods Dependencies

1.  **Check for Outdated Pods**:
    ```bash
    bundle exec pod outdated
    ```
2.  **Update Specific Pod(s)**: Modify the version constraint in the `Podfile` if necessary, then run:
    ```bash
    bundle exec pod update [PodName]
    ```
3.  **Update All Pods**: (Use with caution, test thoroughly)
    ```bash
    bundle exec pod update
    ```
4.  **Commit Changes**: Commit the updated `Podfile.lock` to source control.

### Updating SPM Dependencies

1.  **Identify New Version**: Find the desired new version tag/commit hash for the package.
2.  **Update `Package.swift`**: Change the `.exact("x.y.z")` constraint to the new version.
3.  **Update `Signal.xcworkspace/swift-packages.json`**: Update the `version` and `revision` (commit hash) for the corresponding package pin.
4.  **Resolve in Xcode**: Open the project in Xcode and go to File > Packages > Resolve Package Versions. Xcode will fetch the updated package based on the new constraints.
5.  **Verify `Package.resolved`**: Check the `Signal.xcworkspace/xcshareddata/swiftpm/Package.resolved` file to confirm Xcode resolved to the intended version.
6.  **Test Thoroughly**: Build the project and run tests to ensure the update didn't introduce regressions.
7.  **Commit Changes**: Commit the updated `Package.swift`, `swift-packages.json`, and `Package.resolved` files.

## Migration Strategy: CocoaPods to SPM

The plan for gradually migrating dependencies from CocoaPods to SPM:

1.  **Phase 1 - Swift Utilities** (Complete):
    -   Migrated pure Swift utilities (argument-parser, logging, collections, algorithms, numerics, atomics, async-algorithms, crypto).
    -   Added root `Package.swift` and `swift-packages.json`.
    -   Corrected target path for `SignalCore` module to `SignalCore/Sources`.

2.  **Phase 2 - AWS SDK** (In Progress):
    -   AWS SDK added via SPM (`aws-sdk-ios-spm`) in `Package.swift`.
    -   Currently, AWS pods are still listed in `Podfile`. Future work involves removing the Podfile entries and ensuring the SPM versions are used correctly by the DCD module and potentially other targets.

3.  **Phase 3 - UI Components**:
    -   Evaluate SPM support for components like BonMot, PureLayout, lottie-ios.
    -   Migrate if stable SPM versions exist and integrate cleanly.
    -   Keep legacy UI components in CocoaPods until suitable SPM alternatives are available or supported.

4.  **Phase 4 - Database & Core Libraries**:
    -   Evaluate SPM support for SQLCipher and the specific configuration needed for GRDB.swift/SQLCipher.
    -   Investigate SPM distribution options for LibSignalClient and SignalRingRTC (complex native libraries). This is likely the most challenging phase.

5.  **Final Phase - Full Migration**:
    -   Complete migration of all dependencies where possible.
    -   Maintain CocoaPods only for dependencies that absolutely cannot be migrated (e.g., due to build process requirements, lack of SPM support).

**Priority Order for Migration:**
1.  Swift-native utilities (Done)
2.  AWS SDK components (In Progress - Needs Podfile cleanup)
3.  UI libraries with good SPM support
4.  Database dependencies
5.  Core Signal libraries (likely last due to complexity)

## Examples

### Example 1: Adding a Simple Swift Logger (Using SPM)

1.  Add to `Package.swift`:
    ```swift
    // In dependencies:
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.6.3"), // Use latest verified version
    // In target dependencies:
    .product(name: "Logging", package: "swift-log"),
    ```

2.  Add Pin to `Signal.xcworkspace/swift-packages.json`:
    *(Ensure revision and version match the exact pin used)*
    ```json
    {
      "identity": "swift-log",
      "kind": "remote",
      "location": "https://github.com/apple/swift-log.git",
      "state": {
        "revision": "3d8596ed08bd13520157f0355e35caed215ffbfa",
        "version": "1.6.3"
      },
      "description": "A logging API for Swift."
    }
    ```

3.  Resolve in Xcode (File > Packages > Resolve Package Versions).

4.  Import and use:
    ```swift
    import Logging
    let logger = Logger(label: "com.signal.myfeature")
    logger.info("Feature initialized.")
    ```

### Example 2: Adding a UI Component (Using CocoaPods)

1.  Add to `Podfile`:
    ```ruby
    target 'Signal' do
      # ... other pods
      pod 'NewAwesomeUI', '~> 3.0'
    end
    # Also add to SignalUI target if needed there
    target 'SignalUI' do
      # ... other pods
      pod 'NewAwesomeUI', '~> 3.0'
    end
    ```

2.  Run installation:
    ```bash
    make dependencies
    ```

3.  Import and use:
    ```swift
    import NewAwesomeUI
    let view = NewAwesomeView()
    ```

## Conclusion

Signal iOS employs a hybrid dependency management system. CocoaPods handles complex native libraries, forks, and legacy integrations for the main app targets, while SPM manages modern Swift utilities and AWS dependencies for specific modules (`SignalCore`, `DuplicateContentDetection`, etc.). This hybrid approach allows for incremental migration without disrupting development. Developers should understand which system manages which dependency for a given target and follow the appropriate workflow when adding or updating libraries. Prefer SPM for new Swift-native dependencies where feasible. **Crucially, use the `aws-sdk-ios-spm` package in `Package.swift` for AWS dependencies within SPM-managed modules and avoid adding corresponding pods in the `Podfile` for those targets.** Continue using CocoaPods for dependencies that require its specific capabilities (like core Signal libraries) until they can be safely migrated.