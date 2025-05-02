import Foundation
import AWSDynamoDB
import CommonCrypto

// MARK: - Signature Cache

final class SignatureCache {
    private let cache = NSCache<NSString, NSString>()
    private let queue = DispatchQueue(label: "com.signal.signaturecache")
    
    static let shared = SignatureCache()
    
    private init() {
        cache.countLimit = 1000 // Adjust based on memory constraints
    }
    
    func store(_ signature: String, forHash hash: String) {
        queue.async {
            self.cache.setObject(signature as NSString, forKey: hash as NSString)
        }
    }
    
    func signature(forHash hash: String) -> String? {
        queue.sync {
            return cache.object(forKey: hash as NSString) as String?
        }
    }
    
    func clear() {
        queue.async {
            self.cache.removeAllObjects()
        }
    }
    
    // MARK: - Cache Persistence
    
    private let persistenceQueue = DispatchQueue(label: "com.signal.cachepersistence")
    private let persistenceFile: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("signature_cache.plist")
    }()
    
    func loadFromDisk() {
        persistenceQueue.async {
            do {
                let data = try Data(contentsOf: self.persistenceFile)
                if let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] {
                    self.queue.sync {
                        dict.forEach { hash, signature in
                            self.cache.setObject(signature as NSString, forKey: hash as NSString)
                        }
                    }
                }
            } catch {
                print("Failed to load cache from disk: \(error)")
            }
        }
    }
    
    func saveToDisk() {
        persistenceQueue.async {
            do {
                var dict: [String: String] = [:]
                self.queue.sync {
                    self.cache.enumerateKeysAndObjects { key, value, _ in
                        dict[key as String] = value as String
                    }
                }
                
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: self.persistenceFile)
            } catch {
                print("Failed to save cache to disk: \(error)")
            }
        }
    }
}

// MARK: - Batch Processing

class BatchProcessor {
    private let batchSize = 25 // DynamoDB maximum batch size
    private let queue = DispatchQueue(label: "com.signal.batchprocessor", attributes: .concurrent)
    private var pendingOperations: [(Data, (Result<String, Error>) -> Void)] = []
    private let semaphore = DispatchSemaphore(value: 1)
    private var batchTimer: DispatchSourceTimer?
    private let retryStrategy = RetryStrategy()
    
    init() {
        setupBatchTimer()
    }
    
    private func setupBatchTimer() {
        batchTimer = DispatchSource.makeTimerSource(queue: queue)
        batchTimer?.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        batchTimer?.setEventHandler { [weak self] in
            self?.processPendingBatch()
        }
        batchTimer?.resume()
    }
    
    func addOperation(data: Data, completion: @escaping (Result<String, Error>) -> Void) {
        semaphore.wait()
        pendingOperations.append((data, completion))
        semaphore.signal()
        
        if pendingOperations.count >= batchSize {
            processPendingBatch()
        }
    }
    
    private func processBatchWithRetry(_ writeRequests: [AWSDynamoDBWriteRequest]) async throws {
        try await retryStrategy.execute {
            let batchWriteInput = AWSDynamoDBBatchWriteItemInput()!
            batchWriteInput.requestItems = ["ImageSignatures": writeRequests]
            
            let startTime = Date()
            let result = try await withCheckedThrowingContinuation { continuation in
                AWSDynamoDB.default().batchWriteItem(batchWriteInput).continueWith { task in
                    if let error = task.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                    return nil
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            CloudWatchMetrics.shared.recordBatchMetrics(
                batchSize: writeRequests.count,
                success: true,
                duration: duration
            )
            
            return result
        }
    }
    
    private func processPendingBatch() {
        semaphore.wait()
        guard !pendingOperations.isEmpty else {
            semaphore.signal()
            return
        }
        
        let operations = Array(pendingOperations.prefix(batchSize))
        pendingOperations.removeFirst(min(batchSize, pendingOperations.count))
        semaphore.signal()
        
        let writeRequests = operations.map { data, _ in
            let hash = calculateHash(data.0)
            return AWSDynamoDBWriteRequest()!.dictionaryValue(
                forKey: "PutRequest",
                withDictionary: [
                    "Item": [
                        "signature": ["S": hash],
                        "timestamp": ["N": "\(Int(Date().timeIntervalSince1970))"]
                    ]
                ]
            )
        }
        
        Task {
            do {
                try await processBatchWithRetry(writeRequests)
                
                // Store in cache and notify success
                operations.enumerated().forEach { index, operation in
                    let hash = self.calculateHash(operation.0)
                    SignatureCache.shared.store(hash, forHash: hash)
                    operation.1(.success(hash))
                }
            } catch {
                // Notify all operations of failure
                operations.forEach { _, completion in
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func calculateHash(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    deinit {
        batchTimer?.cancel()
        batchTimer = nil
    }
}

// MARK: - Performance Optimized Content Store

class OptimizedContentStore {
    private let batchProcessor = BatchProcessor()
    private let operationQueue = OperationQueue()
    private var rateLimiter: DispatchSemaphore
    private let retryStrategy = RetryStrategy()
    
    init(maxConcurrentOperations: Int = 10) {
        operationQueue.maxConcurrentOperationCount = maxConcurrentOperations
        rateLimiter = DispatchSemaphore(value: maxConcurrentOperations)
    }
    
    func processContent(_ data: Data) async throws -> String {
        let startTime = Date()
        
        // Check cache first
        let hash = calculateHash(data)
        if let cachedSignature = SignatureCache.shared.signature(forHash: hash) {
            CloudWatchMetrics.shared.recordCacheMetrics(hit: true, size: data.count)
            return cachedSignature
        }
        
        CloudWatchMetrics.shared.recordCacheMetrics(hit: false, size: data.count)
        
        // Rate limiting
        rateLimiter.wait()
        defer { rateLimiter.signal() }
        
        return try await withCheckedThrowingContinuation { continuation in
            batchProcessor.addOperation(data: data) { result in
                let duration = Date().timeIntervalSince(startTime)
                CloudWatchMetrics.shared.recordOperationMetrics(
                    operation: "processContent",
                    duration: duration,
                    success: result.isSuccess,
                    dataSize: data.count
                )
                
                switch result {
                case .success(let signature):
                    continuation.resume(returning: signature)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func calculateHash(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Performance Optimized Message Sender

class OptimizedMessageSender {
    private let contentStore: OptimizedContentStore
    private let rateLimiter: DispatchSemaphore
    
    init(maxConcurrentOperations: Int = 10) {
        self.contentStore = OptimizedContentStore(maxConcurrentOperations: maxConcurrentOperations)
        self.rateLimiter = DispatchSemaphore(value: maxConcurrentOperations)
    }
    
    func sendMessage(_ message: Message) async throws -> SendResult {
        guard let attachment = message.attachments?.first,
              let data = attachment.data else {
            return SendResult(success: false, error: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
        }
        
        // Rate limiting
        rateLimiter.wait()
        defer { rateLimiter.signal() }
        
        do {
            let signature = try await contentStore.processContent(data)
            return SendResult(success: true, error: nil)
        } catch {
            return SendResult(success: false, error: error)
        }
    }
}

// MARK: - Retry Strategy

class RetryStrategy {
    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let jitterFactor: Double
    
    init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        jitterFactor: Double = 0.1
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = jitterFactor
    }
    
    func execute<T>(
        operation: @escaping () async throws -> T,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        var attempt = 0
        
        repeat {
            do {
                return try await operation()
            } catch {
                lastError = error
                attempt += 1
                
                if attempt >= maxRetries || !shouldRetry(error) {
                    throw error
                }
                
                let delay = calculateDelay(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        } while attempt < maxRetries
        
        throw lastError!
    }
    
    private func calculateDelay(attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: -jitterFactor...jitterFactor) * exponentialDelay
        return min(exponentialDelay + jitter, maxDelay)
    }
} 