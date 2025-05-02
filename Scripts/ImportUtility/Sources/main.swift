// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import AWSS3
import AWSDynamoDB
import CommonCrypto

// Configuration
let bucketName = "signal-content-bucket"
let tableName = "ImageSignatures"

// Initialize AWS services
let s3 = AWSS3.default()
let dynamoDB = AWSDynamoDB.default()

// Function to calculate SHA-256 hash
func calculateSHA256(data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
        _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}

// Function to process S3 object
func processS3Object(key: String) async throws {
    print("Processing object: \(key)")
    
    // Download object from S3
    let downloadRequest = AWSS3GetObjectRequest()!
    downloadRequest.bucket = bucketName
    downloadRequest.key = key
    
    let downloadResult = try await withCheckedThrowingContinuation { continuation in
        s3.getObject(downloadRequest).continueWith { task in
            if let error = task.error {
                continuation.resume(throwing: error)
            } else if let result = task.result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: NSError(domain: "S3Error", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result from S3"]))
            }
            return nil
        }
    }
    
    guard let data = downloadResult.body as? Data else {
        throw NSError(domain: "S3Error", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data format"])
    }
    
    // Calculate hash
    let hash = calculateSHA256(data: data)
    print("Generated hash: \(hash)")
    
    // Store in DynamoDB
    let putItemInput = AWSDynamoDBPutItemInput()!
    putItemInput.tableName = tableName
    
    let sigValue = AWSDynamoDBAttributeValue()!
    sigValue.s = hash
    
    let timestampValue = AWSDynamoDBAttributeValue()!
    timestampValue.n = String(Date().timeIntervalSince1970)
    
    let keyValue = AWSDynamoDBAttributeValue()!
    keyValue.s = key
    
    putItemInput.item = [
        "signature": sigValue,
        "timestamp": timestampValue,
        "s3_key": keyValue
    ]
    
    try await withCheckedThrowingContinuation { continuation in
        dynamoDB.putItem(putItemInput).continueWith { task in
            if let error = task.error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: ())
            }
            return nil
        }
    }
    
    print("Successfully processed object: \(key) with hash: \(hash)")
}

// Main function
func main() async throws {
    print("Starting import process...")
    
    // List objects in S3 bucket
    let listRequest = AWSS3ListObjectsV2Request()!
    listRequest.bucket = bucketName
    
    let listResult = try await withCheckedThrowingContinuation { continuation in
        s3.listObjectsV2(listRequest).continueWith { task in
            if let error = task.error {
                continuation.resume(throwing: error)
            } else if let result = task.result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: NSError(domain: "S3Error", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result from S3"]))
            }
            return nil
        }
    }
    
    guard let contents = listResult.contents else {
        print("No objects found in bucket")
        return
    }
    
    print("Found \(contents.count) objects in bucket")
    
    // Process each object
    for object in contents {
        if let key = object.key {
            do {
                try await processS3Object(key: key)
            } catch {
                print("Error processing object \(key): \(error)")
            }
        }
    }
}

// Run the script
print("Import utility starting...")

// Initialize AWS credentials
let credentialsProvider = AWSStaticCredentialsProvider(
    accessKey: ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] ?? "",
    secretKey: ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] ?? ""
)

let configuration = AWSServiceConfiguration(
    region: .USEast1,
    credentialsProvider: credentialsProvider
)

AWSServiceManager.default().defaultServiceConfiguration = configuration

// Run main function
Task {
    do {
        try await main()
        print("Import completed successfully")
    } catch {
        print("Error: \(error)")
    }
    exit(0)
}

// Keep the script running
RunLoop.main.run()
