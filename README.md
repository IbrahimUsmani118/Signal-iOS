# Signal iOS - Duplicate Content Detection

This module provides duplicate content detection functionality for the Signal iOS application using AWS services.

## Requirements

- iOS 15.0+
- Xcode 13.0+
- Swift 5.7+
- AWS Account with appropriate permissions

## Setup

1. Clone the repository
2. Install dependencies:
   ```bash
   pod install
   ```
3. Set up AWS credentials:
   - Create a `.env` file in the project root
   - Add the following environment variables:
     ```
     AWS_ACCESS_KEY_ID=your_access_key
     AWS_SECRET_ACCESS_KEY=your_secret_key
     AWS_SESSION_TOKEN=your_session_token
     ```

## Project Structure

- `SignalCore/` - Core utilities and shared functionality
- `DuplicateContentDetection/` - Main module for duplicate content detection
  - `Services/` - AWS service integration
  - `Tests/` - Test suite
- `MyTool/` - Command-line utility

## Testing

Run the test suite using:
```bash
xcodebuild test -scheme DuplicateContentDetectionTests
```

## Security Notes

- Never commit AWS credentials to version control
- Use environment variables or a secure credential management system
- Rotate credentials regularly
- Follow AWS best practices for IAM permissions

## License

AGPL-3.0-only
