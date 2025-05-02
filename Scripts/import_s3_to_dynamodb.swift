#!/usr/bin/env swift

import Foundation
import AWSS3
import AWSDynamoDB
import CommonCrypto

// AWS credentials from environment
let accessKey = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] ?? ""
let secretKey = ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] ?? ""
let sessionToken = ProcessInfo.processInfo.environment["AWS_SESSION_TOKEN"] ?? ""

// Configuration
let bucketName = "signal-content-bucket"
let tableName = "ImageSignatures"
let region = "us-east-1"

// Initialize AWS services
let s3 = AWSS3.default()
let dynamoDB = AWSDynamoDB.default()

// AWS CLI commands
func listS3Objects() throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/aws")
    process.arguments = ["s3", "ls", "s3://\(bucketName)", "--recursive"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    return output.components(separatedBy: .newlines)
        .filter { !$0.isEmpty }
        .map { line in
            let components = line.components(separatedBy: .whitespaces)
            return components.last ?? ""
        }
}

func downloadS3Object(key: String) throws -> Data {
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/aws")
    process.arguments = ["s3", "cp", "s3://\(bucketName)/\(key)", tempFile.path]
    
    try process.run()
    process.waitUntilExit()
    
    let data = try Data(contentsOf: tempFile)
    try FileManager.default.removeItem(at: tempFile)
    
    return data
}

// Function to calculate SHA-256 hash
func calculateSHA256(data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
        _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}

func storeInDynamoDB(signature: String, key: String) throws {
    let timestamp = Int(Date().timeIntervalSince1970)
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/aws")
    process.arguments = [
        "dynamodb", "put-item",
        "--table-name", tableName,
        "--item", """
        {
            "signature": {"S": "\(signature)"},
            "timestamp": {"N": "\(timestamp)"},
            "s3_key": {"S": "\(key)"}
        }
        """
    ]
    
    try process.run()
    process.waitUntilExit()
}

// Main processing function
func processS3Object(key: String) throws {
    print("Processing object: \(key)")
    
    let data = try downloadS3Object(key: key)
    let hash = calculateSHA256(data: data)
    
    print("Generated hash: \(hash)")
    try storeInDynamoDB(signature: hash, key: key)
    
    print("Successfully processed object: \(key) with hash: \(hash)")
}

// Main execution
print("Import utility starting...")

do {
    let objects = try listS3Objects()
    print("Found \(objects.count) objects in bucket")
    
    for key in objects {
        do {
            try processS3Object(key: key)
        } catch {
            print("Error processing object \(key): \(error)")
        }
    }
    
    print("Import completed successfully")
} catch {
    print("Error: \(error)")
}

// Keep the script running
RunLoop.main.run() 