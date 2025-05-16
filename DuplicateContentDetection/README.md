# Duplicate Content Detection

A module for detecting duplicate content in Signal iOS, leveraging AWS services for efficient content hash checking and storage.

## Overview

This module provides a mechanism to detect duplicate content by generating and comparing content hashes. It uses AWS services (DynamoDB, API Gateway) to efficiently store and query content signatures.

## Key Components

### Services

- **DCDAWSConfig**: Configuration management for AWS services including credentials, endpoints, and retry policies
- **DCDGlobalSignatureService**: Core service for managing content hash signatures in DynamoDB
- **DCDAPIGatewayClient**: Client for interacting with AWS API Gateway services

## Dependencies

This module depends on the following:
- AWSCore
- AWSDynamoDB
- AWSCognitoIdentity
- SignalCore (using SignalCoreUtility)
- Logging

## Usage

### Initialization

The services are designed as singletons. Before using them, ensure AWS credentials are set up:

```swift
// Initialize AWS configuration
AWSConfig.setupAWSCredentials()

// The services can then be accessed through their shared instances
let signatureService = GlobalSignatureService.shared
let apiClient = APIGatewayClient.shared
```

### Content Hash Checking

To check if a content hash exists:

```swift
let contentHash = "base64EncodedHash..."
let exists = await GlobalSignatureService.shared.contains(contentHash)

if exists {
    // Handle duplicate content
} else {
    // Process new content
    // Optionally store the hash if validated
    await GlobalSignatureService.shared.store(contentHash)
}
```

### API Gateway Requests

To interact with AWS API Gateway endpoints:

```swift
do {
    let response = try await APIGatewayClient.shared.request(
        endpoint: AWSConfig.apiGatewayEndpoint,
        method: .get,
        apiKey: AWSConfig.apiKey,
        queryItems: ["param": "value"]
    )
    
    // Process response data
} catch {
    // Handle error
}
```

## Error Handling

All services implement retry logic with exponential backoff for transient errors. Permanent errors are propagated to the caller for handling.

## Logging

The module uses the Swift Logging API for consistent logging. Additionally, all important operations are logged through SignalCoreUtility for integration with Signal's logging infrastructure. 