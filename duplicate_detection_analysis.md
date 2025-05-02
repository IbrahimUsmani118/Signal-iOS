# Duplicate Content Detection System: Architecture and Implementation Analysis

## 1. Purpose and Goals

The Duplicate Content Detection (DCD) system is a critical feature within Signal iOS designed to enhance network security and efficiency. Its primary goals are:

-   **Security**: Prevent the distribution and download of known harmful or undesirable content by checking attachments against a global database of content hashes.
-   **Efficiency**: Reduce redundant data transfer and storage by identifying duplicate attachments.
-   **Privacy**: Utilize cryptographic hashes (SHA-256) to identify content without exposing the raw content itself.
-   **Resilience**: Ensure the system fails open (defaults to allowing content) during AWS service disruptions or configuration errors to avoid blocking legitimate communication.
-   **Scalability**: Leverage scalable AWS services (DynamoDB, API Gateway, Lambda) to handle a large volume of checks.

## 2. System Architecture

The DCD system is composed of several key components interacting across different layers of the application and leveraging AWS services.

### 2.1 Core Components

1.  **`AWSConfig`** (`DuplicateContentDetection/Services/AWSConfig.swift`):
    -   Centralizes AWS configuration constants (Region: `us-east-1`, Cognito Pool ID, DynamoDB Table: `SignalContentHashes`, API Endpoints, Retry settings).
    -   Provides the `setupAWSCredentials()` method using `AWSCognitoCredentialsProvider`.
    -   Offers helper functions for getting AWS clients (`getDynamoDBClient()`) and validating connectivity (`validateAWSCredentials`, `validateAPIGatewayConnectivity`).

2.  **`AWSCredentialsVerificationManager`** (`DuplicateContentDetection/Services/AWSCredentialsVerificationManager.swift`):
    -   A singleton service responsible for comprehensive verification of AWS credentials and service connectivity (Cognito, DynamoDB, API Gateway).
    -   Used during app launch (`AppDelegate`) to ensure the AWS environment is correctly configured before the DCD system becomes fully operational.
    -   Generates diagnostic reports for troubleshooting.

3.  **`APIGatewayClient`** (`DuplicateContentDetection/Services/APIGatewayClient.swift`):
    -   Handles authenticated HTTP requests (GET, POST, PUT, DELETE) to the configured AWS API Gateway endpoints.
    -   Integrates with `AWSConfig` to retrieve endpoint URLs and necessary headers (including API Key if configured).
    -   Implements retry logic for API calls based on HTTP status codes and network errors, using `AWSConfig.calculateBackoffDelay()`.

4.  **`GlobalSignatureService`** (`SignalServiceKit/Network/GlobalSignatureService.swift`):
    -   Acts as the primary abstraction layer for the application logic to interact with the DCD backend.
    -   Provides methods like `contains(hash:)`, `store(hash:)`, `delete(hash:)`, `batchContains(hashes:)`, `batchImportHashes(hashes:)`.
    -   Internally uses `APIGatewayClient` (or direct `URLSession`) to communicate with the backend API Gateway.
    -   Implements retry logic for its operations.
    -   Manages batch import jobs via `S3toDynamoDBImporter` and `BatchImportJobTracker`.
    -   Collects operational metrics.

5.  **`AttachmentDownloadHook`** (`Signal/Attachments/AttachmentDownloadHook.swift`):
    -   Intercepts attachment download requests within the app.
    -   Computes the SHA-256 hash of the attachment data.
    -   Calls `GlobalSignatureService.contains(hash:)` to check if the hash exists in the global database.
    -   If the hash exists, the download is blocked (returns `false`), otherwise allowed (returns `true`).
    -   Defaults to allowing the download if hash computation fails or `GlobalSignatureService` check encounters an error.

6.  **`MessageSender` Integration** (`SignalServiceKit/Messages/MessageSender.swift` - Conceptual):
    -   **Pre-Send Check**: Before sending a message with an attachment, computes the hash and calls `GlobalSignatureService.contains(hash:)`. If `true`, the send is blocked, and a `MessageSenderError.duplicateBlocked` error is raised.
    -   **Post-Send Storage**: After a message with an attachment is successfully sent, it asynchronously calls `GlobalSignatureService.store(hash:)` in a background task to contribute the hash to the global database. This storage attempt happens only if the send was successful.

### 2.2 AWS Services Interaction

-   **Cognito Identity Pool**: Provides temporary AWS credentials to the iOS client (`AWSConfig` uses `AWSCognitoCredentialsProvider`).
-   **API Gateway**: Exposes HTTP endpoints (`AWSConfig.apiGatewayEndpoint`, `AWSConfig.getTagApiGatewayEndpoint`) that the `APIGatewayClient` (used by `GlobalSignatureService`) calls. These endpoints likely trigger backend Lambda functions.
-   **Lambda** (`signal-content-processor`): Backend functions (triggered by API Gateway) that contain the core logic to interact with DynamoDB (checking, storing, deleting hashes).
-   **DynamoDB** (`SignalContentHashes` table): The persistent storage for content hashes, accessed by the backend Lambda functions. Attributes include `ContentHash` (PK), `Timestamp`, `TTL`.
-   **S3** (`signal-content-attachments` bucket): Likely used for batch import operations managed by `S3toDynamoDBImporter`.

(Refer to `aws_flow_analysis.md` for a more detailed dependency chain.)

## 3. Workflow: Attachment Handling

### 3.1 Attachment Send Flow

1.  User attempts to send a message with an attachment.
2.  `MessageSender` obtains the attachment data and computes its SHA-256 hash.
3.  `MessageSender` calls `GlobalSignatureService.contains(hash:)`.
4.  `GlobalSignatureService` uses `APIGatewayClient` to call the "checkHash" (GetTag) API Gateway endpoint.
5.  The backend (Lambda/DynamoDB) checks if the hash exists.
6.  API Gateway returns the result to `GlobalSignatureService`.
7.  **If `contains` returns `true`**:
    -   `MessageSender` blocks the send operation.
    -   A `MessageSenderError.duplicateBlocked` error is generated.
8.  **If `contains` returns `false`**:
    -   `MessageSender` proceeds with the normal message sending process.
    -   **If the message send SUCCEEDS**: `MessageSender` calls `GlobalSignatureService.store(hash:)` asynchronously in a background task to contribute the hash to the global database.
    -   `GlobalSignatureService` uses `APIGatewayClient` to call the "storeHash" (General) API Gateway endpoint.
    -   The backend (Lambda/DynamoDB) stores the hash with a timestamp and TTL.
    -   **If the message send FAILS** (for reasons other than duplicate content): `GlobalSignatureService.store(hash:)` is **NOT** called.

### 3.2 Attachment Download Flow

1.  User receives a message with an attachment pointer and attempts to download the attachment.
2.  `AttachmentDownloadHook` intercepts the download request.
3.  The hook accesses the attachment data (e.g., from a temporary file or memory) and computes its SHA-256 hash.
4.  `AttachmentDownloadHook` calls `GlobalSignatureService.contains(hash:)`.
5.  `GlobalSignatureService` interacts with the backend via API Gateway (as described above) to check hash existence.
6.  **If `contains` returns `true`**:
    -   `AttachmentDownloadHook` returns `false`, blocking the download.
    -   The blocked state might be reported or logged.
7.  **If `contains` returns `false` OR if any error occurs during hashing or the `contains` check**:
    -   `AttachmentDownloadHook` returns `true`, allowing the download to proceed.

## 4. Testing Strategy

The DCD system is validated through a multi-layered testing approach:

1.  **Unit Tests**: Individual functions and classes are tested in isolation. Mocks are used for external dependencies.
    -   **Example**: Testing hash computation logic, testing `AWSConfig.calculateBackoffDelay()`.
    -   **Mocks**: `AWSServiceMock` provides mock implementations for Cognito, DynamoDB, and API Gateway interactions, allowing tests to run without real AWS credentials.

2.  **Component Tests**: Test the interaction and logic within specific DCD components, often using mocks for adjacent services.
    -   `test_global_signature_service.swift`: Validates `GlobalSignatureService` logic (contains, store, delete, batch, metrics) potentially using mock AWS clients or hitting real AWS if `runValidationTestsAgainstRealAWS` is true.
    -   `test_attachment_download_hook.swift`: Tests `AttachmentDownloadHook` using a mocked `GlobalSignatureService` to simulate blocked/allowed scenarios and error conditions.
    -   `test_message_sender_integration.swift`: Simulates the parts of `MessageSender` that interact with `GlobalSignatureService` (using a mock GSS) to verify the pre-send check and post-send store logic.

3.  **Verification Scripts**: Standalone scripts designed to verify the configuration and connectivity of the required AWS services.
    -   `AWSVerificationTestScript.swift`: Runs a sequence of checks against Cognito, DynamoDB, API Gateway, and S3. Can run in live or mock mode. Outputs detailed results to `aws_dependency_verification.log` and `aws_dependency_verification.md`.
    -   `AwsCredentialsVerifier.swift` (XCTest based): Provides similar verification checks within the XCTest framework, logging to `aws_verification_results.log`.

4.  **End-to-End Validation**: Although less formalized in the provided file structure, end-to-end testing involves running the app (manually or via UI tests) and verifying that sending/downloading specific known-bad or duplicate content is correctly blocked, while normal content works as expected. This requires a fully configured AWS backend.

## 5. Common Issues and Troubleshooting

Refer to `aws_flow_analysis.md#5-troubleshooting-aws-connectivity-issues` for a detailed troubleshooting guide. Key steps include:

1.  **Check Application Logs**: Look for errors from `AWSConfig`, `AWSCredentialsVerificationManager`, `GlobalSignatureService`, `APIGatewayClient`. Check for specific AWS error codes/domains.
2.  **Run Verification Scripts/Tests**: Use `AWSVerificationTestScript.swift` or `AwsCredentialsVerifier.swift` to pinpoint issues with specific services (Cognito, DynamoDB, API Gateway). Examine their log outputs (`aws_dependency_verification.log`, `aws_verification_results.log`).
3.  **Validate Configuration**: Double-check constants in `AWSConfig.swift` against the `aws-config.json` and the actual AWS environment setup (Region, Pool ID, Table Name, Endpoints). Ensure API Key placeholders are replaced if needed.
4.  **Check Network**: Confirm device connectivity. Use `curl` or other tools to test reachability of API Gateway endpoints directly.
5.  **Check AWS Console**:
    -   Verify Cognito Identity Pool configuration and associated IAM role permissions.
    -   Verify DynamoDB table (`SignalContentHashes`) exists, is `ACTIVE`, has the correct primary key (`ContentHash`), and TTL is enabled on the `TTL` attribute.
    -   Check API Gateway deployment status and logs (if available).
    -   Check Lambda function (`signal-content-processor`) configuration, environment variables, and execution logs (if available).
    -   Check S3 bucket (`signal-content-attachments`) existence and permissions (if relevant to the issue).
6.  **Check IAM Permissions**: Ensure the IAM role linked to the Cognito Identity Pool has necessary permissions (`dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` on the table; `execute-api:Invoke` on the API Gateway; potentially `lambda:InvokeFunction`).

## 6. Next Steps for Xcode Testing and Validation

1.  **Open Workspace**: Open the project using `Signal.xcworkspace`.
2.  **Build Project**: Build the `Signal` scheme to ensure all dependencies (CocoaPods & SPM) are resolved and the code compiles.
3.  **Run Unit/Component Tests**:
    -   Navigate to the Test navigator (Cmd+6).
    -   Run specific test targets:
        -   `SignalServiceKitTests` (includes `TestGlobalSignatureService` if integrated there).
        -   `SignalTests` (includes `TestAttachmentDownloadHook`, `TestMessageSenderIntegration` if integrated there).
        -   Potentially a dedicated `DuplicateContentDetectionTests` target if created.
    -   Run individual test files (e.g., `test_global_signature_service.swift`) by right-clicking and selecting "Run Test Methods".
4.  **Run Verification Tests (XCTest)**:
    -   Locate `AwsCredentialsVerifier.swift` in the Test navigator.
    -   Run the tests within this class. Check console output and the `aws_verification_results.log` file.
    -   Modify the `runValidationTestsAgainstRealAWS` flag in relevant test files (`TestS3Service`, `TestLambdaService`, `TestGlobalSignatureService`) if you want to execute tests requiring live AWS interaction (ensure credentials are set up correctly on your machine/simulator).
5.  **Run Verification Script (Standalone)**:
    -   Open a terminal in the project root.
    -   Execute the script: `swift DuplicateContentDetection/Tests/AWSVerificationTestScript.swift`
    -   To run in mock mode: `MOCK_MODE=1 swift DuplicateContentDetection/Tests/AWSVerificationTestScript.swift`
    -   Check console output and the `aws_dependency_verification.log` file.
6.  **Manual App Testing**:
    -   Run the `Signal` app on a simulator or device.
    -   Observe logs during startup for AWS initialization messages from `AppDelegate`.
    -   Attempt to send/receive attachments. If the backend is fully configured with known blocked hashes, test if blocking occurs as expected. Check logs for DCD activity.

## 7. Recommendations for Security and Reliability

### 7.1 Security

1.  **IAM Least Privilege**: Regularly review and tighten IAM permissions for the Cognito role to ensure it only has the *minimum* necessary access (`dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` on the specific table ARN; `execute-api:Invoke` on specific API Gateway resources). Avoid wildcard permissions.
2.  **API Key Management**: If API Gateway uses API Keys, ensure the key (`AWSConfig.apiKey`) is **not** hardcoded. Retrieve it securely at runtime (e.g., from a configuration service or encrypted store). Implement key rotation policies.
3.  **API Gateway Authorizers**: If API Key auth is not used, ensure API Gateway endpoints use appropriate IAM authorizers linked to the Cognito credentials to prevent unauthorized access.
4.  **Input Validation**: Ensure backend Lambda functions perform strict validation of input received from API Gateway (e.g., hash format, length) to prevent injection or processing errors.
5.  **Monitoring & Alerting**: Set up CloudWatch alarms for unusual API Gateway traffic patterns, high error rates on Lambda/DynamoDB, or unauthorized access attempts (using CloudTrail).

### 7.2 Reliability & Performance

1.  **Enhanced Retry Logic**: Implement more sophisticated retry strategies, potentially including circuit breaking (using libraries or custom logic) in `GlobalSignatureService` or `APIGatewayClient` to prevent hammering failing services.
2.  **Client-Side Caching**: Implement a short-lived, in-memory cache (e.g., LRU cache) within `GlobalSignatureService` or `AttachmentDownloadHook` for `contains` results. This can significantly reduce redundant API calls for frequently checked hashes, lowering latency and cost.
3.  **DynamoDB Capacity**: Ensure the `SignalContentHashes` table uses On-Demand capacity mode (as configured) or has adequate provisioned throughput with auto-scaling enabled to handle load spikes.
4.  **Batch Operations**: Leverage DynamoDB `BatchGetItem` or API Gateway batch endpoints (if available/implemented on the backend) for operations like `batchContains`. This reduces network overhead compared to multiple individual requests.
5.  **Asynchronous Processing**: Ensure all AWS interactions (`contains`, `store`) remain non-blocking to the main thread, especially hash computation for large files and the post-send `store` operation.
6.  **Multi-Region Strategy (Advanced)**: For high availability, consider deploying the backend (API Gateway, Lambda, DynamoDB Global Tables) across multiple AWS regions, although this significantly increases complexity.