import Foundation
import AWSDynamoDB
import AWSS3

// MARK: - Debug Configuration

struct DebugConfig {
    static let shared = DebugConfig()
    
    var enableVerboseLogging = false
    var enablePerformanceLogging = true
    var enableValidationChecks = true
    var enableMemoryMonitoring = false
    var enableNetworkMonitoring = true
    var enableCacheDebugging = true
    var enableDetailedValidation = true
    var enableResourceMonitoring = true
    var enableErrorTracking = true
    var enableCacheValidation = true
    var enableDataIntegrityChecks = true
    var enableNetworkLatencyMonitoring = true
    var enableDetailedMemoryProfiling = false
}

// MARK: - Debug Logger

final class DebugLogger {
    static let shared = DebugLogger()
    
    private let queue = DispatchQueue(label: "com.signal.debuglogger")
    private let logFile: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("duplicate_content_debug.log")
    }()
    
    private let maxLogSize: UInt64 = 10 * 1024 * 1024 // 10MB
    private let maxLogFiles = 5
    
    private init() {
        setupLogging()
    }
    
    private func setupLogging() {
        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard DebugConfig.shared.enableVerboseLogging || level != .debug else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(file):\(line)] \(function): \(message)\n"
        
        queue.async {
            if let handle = try? FileHandle(forWritingTo: self.logFile) {
                handle.seekToEndOfFile()
                handle.write(logMessage.data(using: .utf8)!)
                handle.closeFile()
            }
        }
        
        // Also print to console for immediate feedback
        print(logMessage)
    }
    
    func clearLogs() {
        queue.async {
            try? "".write(to: self.logFile, atomically: true, encoding: .utf8)
        }
    }
    
    func rotateLogs() {
        queue.async {
            let fileManager = FileManager.default
            let logDirectory = self.logFile.deletingLastPathComponent()
            
            // Check current log size
            if let attributes = try? fileManager.attributesOfItem(atPath: self.logFile.path),
               let size = attributes[.size] as? UInt64,
               size > self.maxLogSize {
                
                // Create backup
                let backupPath = self.logFile.appendingPathExtension("1")
                try? fileManager.moveItem(at: self.logFile, to: backupPath)
                
                // Rotate existing backups
                for i in (1..<self.maxLogFiles).reversed() {
                    let oldPath = self.logFile.appendingPathExtension("\(i)")
                    let newPath = self.logFile.appendingPathExtension("\(i + 1)")
                    try? fileManager.moveItem(at: oldPath, to: newPath)
                }
                
                // Create new log file
                self.setupLogging()
            }
        }
    }
    
    func logError(_ error: Error, context: String = "", file: String = #file, function: String = #function, line: Int = #line) {
        let errorMessage = "\(context.isEmpty ? "" : "\(context): ")\(error.localizedDescription)"
        log(errorMessage, level: .error, file: file, function: function, line: line)
        
        if let nsError = error as NSError? {
            log("Error Domain: \(nsError.domain)", level: .debug)
            log("Error Code: \(nsError.code)", level: .debug)
            log("User Info: \(nsError.userInfo)", level: .debug)
        }
    }
}

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

// MARK: - Validation System

class ContentValidator {
    static let shared = ContentValidator()
    
    private let queue = DispatchQueue(label: "com.signal.validator", attributes: .concurrent)
    private let dynamoDB = AWSDynamoDB.default()
    private let s3 = AWSS3.default()
    
    func validateContent(_ data: Data) async throws -> ValidationResult {
        let startTime = Date()
        let hash = calculateHash(data)
        
        // 1. Check local cache
        if let cachedSignature = SignatureCache.shared.signature(forHash: hash) {
            DebugLogger.shared.log("Cache hit for hash: \(hash)")
            return ValidationResult(
                isValid: true,
                source: .cache,
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        // 2. Check DynamoDB
        let dynamoResult = try await validateInDynamoDB(hash: hash)
        if dynamoResult.isValid {
            DebugLogger.shared.log("Found in DynamoDB: \(hash)")
            return ValidationResult(
                isValid: true,
                source: .dynamoDB,
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        // 3. Check S3 (if applicable)
        if let s3Result = try? await validateInS3(hash: hash) {
            DebugLogger.shared.log("Found in S3: \(hash)")
            return ValidationResult(
                isValid: true,
                source: .s3,
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        return ValidationResult(
            isValid: false,
            source: .none,
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    private func validateInDynamoDB(hash: String) async throws -> ValidationResult {
        let queryInput = AWSDynamoDBQueryInput()!
        queryInput.tableName = "ImageSignatures"
        queryInput.keyConditionExpression = "signature = :hash"
        queryInput.expressionAttributeValues = [
            ":hash": AWSDynamoDBAttributeValue()!.withS(hash)
        ]
        
        let result = try await withCheckedThrowingContinuation { continuation in
            dynamoDB.query(queryInput).continueWith { task in
                if let error = task.error {
                    continuation.resume(throwing: error)
                } else if let result = task.result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result"]))
                }
                return nil
            }
        }
        
        return ValidationResult(
            isValid: result.items?.isEmpty == false,
            source: .dynamoDB,
            duration: 0
        )
    }
    
    private func validateInS3(hash: String) async throws -> ValidationResult? {
        // Implementation for S3 validation if needed
        return nil
    }
    
    private func calculateHash(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    func validateContentWithChecks(_ data: Data) async throws -> DetailedValidationResult {
        let startTime = Date()
        var validationChecks: [ValidationCheck] = []
        
        // Data integrity check
        if DebugConfig.shared.enableDataIntegrityChecks {
            let integrityCheck = try await validateDataIntegrity(data)
            validationChecks.append(integrityCheck)
            if !integrityCheck.isValid {
                return DetailedValidationResult(
                    isValid: false,
                    source: .none,
                    duration: Date().timeIntervalSince(startTime),
                    checks: validationChecks
                )
            }
        }
        
        let hash = calculateHash(data)
        
        // Cache validation
        if DebugConfig.shared.enableCacheValidation {
            let cacheCheck = try await validateCache(hash: hash)
            validationChecks.append(cacheCheck)
            if cacheCheck.isValid {
                return DetailedValidationResult(
                    isValid: true,
                    source: .cache,
                    duration: Date().timeIntervalSince(startTime),
                    checks: validationChecks
                )
            }
        }
        
        // DynamoDB validation
        let dynamoCheck = try await validateInDynamoDB(hash: hash)
        validationChecks.append(dynamoCheck)
        if dynamoCheck.isValid {
            return DetailedValidationResult(
                isValid: true,
                source: .dynamoDB,
                duration: Date().timeIntervalSince(startTime),
                checks: validationChecks
            )
        }
        
        // S3 validation
        if let s3Check = try? await validateInS3(hash: hash) {
            validationChecks.append(s3Check)
            if s3Check.isValid {
                return DetailedValidationResult(
                    isValid: true,
                    source: .s3,
                    duration: Date().timeIntervalSince(startTime),
                    checks: validationChecks
                )
            }
        }
        
        return DetailedValidationResult(
            isValid: false,
            source: .none,
            duration: Date().timeIntervalSince(startTime),
            checks: validationChecks
        )
    }
    
    private func validateDataIntegrity(_ data: Data) async throws -> ValidationCheck {
        let startTime = Date()
        
        // Check for empty data
        guard !data.isEmpty else {
            return ValidationCheck(
                type: .dataIntegrity,
                isValid: false,
                message: "Empty data",
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        // Check for corrupted data (example: image validation)
        if let image = UIImage(data: data) {
            if image.size.width == 0 || image.size.height == 0 {
                return ValidationCheck(
                    type: .dataIntegrity,
                    isValid: false,
                    message: "Invalid image dimensions",
                    duration: Date().timeIntervalSince(startTime)
                )
            }
        }
        
        return ValidationCheck(
            type: .dataIntegrity,
            isValid: true,
            message: "Data integrity verified",
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    private func validateCache(hash: String) async throws -> ValidationCheck {
        let startTime = Date()
        let isValid = SignatureCache.shared.signature(forHash: hash) != nil
        
        return ValidationCheck(
            type: .cache,
            isValid: isValid,
            message: isValid ? "Cache hit" : "Cache miss",
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

struct ValidationResult {
    let isValid: Bool
    let source: ValidationSource
    let duration: TimeInterval
    
    enum ValidationSource {
        case cache
        case dynamoDB
        case s3
        case none
    }
}

// MARK: - Performance Monitor

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let queue = DispatchQueue(label: "com.signal.performance")
    private var metrics: [String: [TimeInterval]] = [:]
    private var memoryUsage: [TimeInterval: UInt64] = [:]
    private var networkStats: [String: NetworkStats] = [:]
    
    struct NetworkStats {
        var bytesSent: UInt64 = 0
        var bytesReceived: UInt64 = 0
        var requestCount: UInt64 = 0
        var errorCount: UInt64 = 0
    }
    
    func recordOperation(_ name: String, duration: TimeInterval) {
        guard DebugConfig.shared.enablePerformanceLogging else { return }
        
        queue.async {
            if self.metrics[name] == nil {
                self.metrics[name] = []
            }
            self.metrics[name]?.append(duration)
            
            // Report to CloudWatch
            CloudWatchMetrics.shared.recordMetric(
                name: "OperationDuration",
                value: duration,
                unit: .seconds,
                dimensions: ["Operation": name]
            )
        }
    }
    
    func recordMemoryUsage() {
        guard DebugConfig.shared.enableMemoryMonitoring else { return }
        
        queue.async {
            let usage = self.getMemoryUsage()
            self.memoryUsage[Date().timeIntervalSince1970] = usage
            
            CloudWatchMetrics.shared.recordMetric(
                name: "MemoryUsage",
                value: Double(usage),
                unit: .bytes
            )
        }
    }
    
    func recordNetworkStats(_ operation: String, bytesSent: UInt64, bytesReceived: UInt64, success: Bool) {
        guard DebugConfig.shared.enableNetworkMonitoring else { return }
        
        queue.async {
            if self.networkStats[operation] == nil {
                self.networkStats[operation] = NetworkStats()
            }
            
            var stats = self.networkStats[operation]!
            stats.bytesSent += bytesSent
            stats.bytesReceived += bytesReceived
            stats.requestCount += 1
            if !success {
                stats.errorCount += 1
            }
            self.networkStats[operation] = stats
            
            // Report to CloudWatch
            CloudWatchMetrics.shared.recordMetric(
                name: "NetworkBytes",
                value: Double(bytesSent + bytesReceived),
                unit: .bytes,
                dimensions: ["Operation": operation]
            )
        }
    }
    
    func generateReport() -> String {
        var report = "Performance Report\n"
        report += "================\n\n"
        
        // Operation metrics
        report += "Operation Metrics:\n"
        metrics.forEach { name, durations in
            let avg = durations.reduce(0, +) / Double(durations.count)
            let max = durations.max() ?? 0
            let min = durations.min() ?? 0
            report += "- \(name):\n"
            report += "  Average: \(String(format: "%.3f", avg))s\n"
            report += "  Min: \(String(format: "%.3f", min))s\n"
            report += "  Max: \(String(format: "%.3f", max))s\n"
        }
        
        // Network stats
        report += "\nNetwork Statistics:\n"
        networkStats.forEach { operation, stats in
            report += "- \(operation):\n"
            report += "  Bytes Sent: \(stats.bytesSent)\n"
            report += "  Bytes Received: \(stats.bytesReceived)\n"
            report += "  Requests: \(stats.requestCount)\n"
            report += "  Errors: \(stats.errorCount)\n"
        }
        
        // Memory usage
        if !memoryUsage.isEmpty {
            report += "\nMemory Usage:\n"
            let currentUsage = getMemoryUsage()
            report += "Current: \(currentUsage) bytes\n"
            report += "Peak: \(memoryUsage.values.max() ?? 0) bytes\n"
        }
        
        return report
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                         task_flavor_t(TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
} 