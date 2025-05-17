import Foundation

public struct AWSConfig {
    // S3 Configuration
    public static let s3BucketName = "<YOUR_S3_BUCKET_NAME>" // e.g., "myawsbucket"
    public static let s3Region = "<YOUR_S3_REGION>" // e.g., "us-east-1"
    public static let s3ImagesPath = "<YOUR_S3_IMAGES_PATH>" // e.g., "images/"
    public static let s3BaseURL = "<YOUR_S3_BASE_URL>" // e.g., "https://<bucket>.s3.<region>.amazonaws.com/<path>"
    
    // API Gateway Configuration
    public static let uploadImageAPIURL = "<YOUR_UPLOAD_IMAGE_API_URL>"
    public static let uploadImageAPIKey = "<YOUR_UPLOAD_IMAGE_API_KEY>"
    
    public static let getTagAPIURL = "<YOUR_GET_TAG_API_URL>"
    public static let getTagAPIKey = "<YOUR_GET_TAG_API_KEY>"
    
    public static let blockImageAPIURL = "<YOUR_BLOCK_IMAGE_API_URL>"
    public static let blockImageAPIKey = "<YOUR_BLOCK_IMAGE_API_KEY>"
    
    // DynamoDB Configuration
    public static let hashTableName = "ImageSignatures"
    public static let dynamoDBRegion = "<YOUR_DYNAMODB_REGION>" // e.g., "us-east-1"
    public static let dynamoDBEndpoint = "<YOUR_DYNAMODB_ENDPOINT>" // e.g., "https://<api>.execute-api.<region>.amazonaws.com/<stage>"
    public static let apiGatewayEndpoint = "<YOUR_API_GATEWAY_ENDPOINT>"
    public static let getTagEndpoint = "<YOUR_GET_TAG_ENDPOINT>"
    
    // Cognito Configuration
    public static let identityPoolId = "<YOUR_IDENTITY_POOL_ID>"
    public static let cognitoRegion = "<YOUR_COGNITO_REGION>"
    public static let apiKey = "<YOUR_API_GATEWAY_API_KEY_PLACEHOLDER>"
    
    // AWS Credentials (for development/testing only, should use secure storage in production)
    public static let accessKeyId = "<YOUR_ACCESS_KEY_ID>"
    public static let secretAccessKey = "<YOUR_SECRET_ACCESS_KEY>"
    public static let sessionToken = "<YOUR_SESSION_TOKEN>"
    
    // DynamoDB Table Fields
    public static let hashFieldName = "ContentHash"
    public static let timestampFieldName = "Timestamp"
    public static let ttlFieldName = "TTL"
    public static let defaultTTLInDays = 30
    
    // Network Configuration
    public static let requestTimeoutSeconds = 30.0
    public static let resourceTimeoutSeconds = 300.0
    public static let maxRetryCount = 3
    public static let initialRetryDelay = 1.0
    public static let maxRetryDelay = 30.0
    
    // Computed property for region value
    public static var region: String {
        return s3Region
    }
} 