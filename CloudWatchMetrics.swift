import Foundation
import AWSCloudWatch

final class CloudWatchMetrics {
    static let shared = CloudWatchMetrics()
    
    private let cloudWatch = AWSCloudWatch.default()
    private let namespace = "Signal/DuplicateContent"
    private let queue = DispatchQueue(label: "com.signal.cloudwatch", attributes: .concurrent)
    private var metricsBuffer: [AWSCloudWatchMetricDatum] = []
    private let bufferSize = 20
    private let flushInterval: TimeInterval = 60 // seconds
    private var flushTimer: DispatchSourceTimer?
    
    private init() {
        setupFlushTimer()
    }
    
    private func setupFlushTimer() {
        flushTimer = DispatchSource.makeTimerSource(queue: queue)
        flushTimer?.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        flushTimer?.setEventHandler { [weak self] in
            self?.flushMetrics()
        }
        flushTimer?.resume()
    }
    
    func recordMetric(
        name: String,
        value: Double,
        unit: AWSCloudWatchStandardUnit = .count,
        dimensions: [String: String] = [:]
    ) {
        queue.async {
            let datum = AWSCloudWatchMetricDatum()!
            datum.metricName = name
            datum.value = NSNumber(value: value)
            datum.unit = unit
            datum.timestamp = Date()
            
            if !dimensions.isEmpty {
                datum.dimensions = dimensions.map { key, value in
                    let dimension = AWSCloudWatchDimension()!
                    dimension.name = key
                    dimension.value = value
                    return dimension
                }
            }
            
            self.metricsBuffer.append(datum)
            
            if self.metricsBuffer.count >= self.bufferSize {
                self.flushMetrics()
            }
        }
    }
    
    private func flushMetrics() {
        guard !metricsBuffer.isEmpty else { return }
        
        let metricsToFlush = metricsBuffer
        metricsBuffer.removeAll()
        
        let input = AWSCloudWatchPutMetricDataInput()!
        input.namespace = namespace
        input.metricData = metricsToFlush
        
        cloudWatch.putMetricData(input).continueWith { task in
            if let error = task.error {
                print("Failed to send metrics to CloudWatch: \(error)")
                // Requeue failed metrics
                self.queue.async {
                    self.metricsBuffer.append(contentsOf: metricsToFlush)
                }
            }
            return nil
        }
    }
    
    deinit {
        flushTimer?.cancel()
        flushTimer = nil
        flushMetrics() // Flush any remaining metrics
    }
}

// MARK: - Metric Categories

extension CloudWatchMetrics {
    func recordOperationMetrics(
        operation: String,
        duration: TimeInterval,
        success: Bool,
        dataSize: Int
    ) {
        recordMetric(
            name: "OperationDuration",
            value: duration,
            unit: .seconds,
            dimensions: ["Operation": operation]
        )
        
        recordMetric(
            name: "OperationSuccess",
            value: success ? 1 : 0,
            unit: .count,
            dimensions: ["Operation": operation]
        )
        
        recordMetric(
            name: "DataSize",
            value: Double(dataSize),
            unit: .bytes,
            dimensions: ["Operation": operation]
        )
    }
    
    func recordCacheMetrics(
        hit: Bool,
        size: Int
    ) {
        recordMetric(
            name: "CacheHit",
            value: hit ? 1 : 0,
            unit: .count
        )
        
        recordMetric(
            name: "CacheSize",
            value: Double(size),
            unit: .bytes
        )
    }
    
    func recordBatchMetrics(
        batchSize: Int,
        success: Bool,
        duration: TimeInterval
    ) {
        recordMetric(
            name: "BatchSize",
            value: Double(batchSize),
            unit: .count
        )
        
        recordMetric(
            name: "BatchSuccess",
            value: success ? 1 : 0,
            unit: .count
        )
        
        recordMetric(
            name: "BatchDuration",
            value: duration,
            unit: .seconds
        )
    }
} 