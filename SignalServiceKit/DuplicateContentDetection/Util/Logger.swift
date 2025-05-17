import Foundation
import CocoaLumberjack

/// Utility class for logging in the duplicate content detection system
public class Logger {
    
    // MARK: - Log Levels
    
    /// Log levels for the duplicate content detection system
    public enum LogLevel: Int {
        case error = 0
        case warn = 1
        case info = 2
        case debug = 3
        case verbose = 4
    }
    
    // MARK: - Properties
    
    /// Current log level (defaults to info in production, debug in development)
    public static var currentLogLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()
    
    /// Whether to log to the console
    public static var logToConsole: Bool = true
    
    /// Whether to log to a file
    public static var logToFile: Bool = true
    
    // MARK: - Initialization
    
    /// Configures the logger for the duplicate content detection system
    public static func configure() {
        if logToConsole {
            DDLog.add(DDOSLogger.sharedInstance)
        }
        
        if logToFile {
            let fileLogger = DDFileLogger()
            fileLogger.rollingFrequency = 60 * 60 * 24 // 24 hours
            fileLogger.logFileManager.maximumNumberOfLogFiles = 7
            DDLog.add(fileLogger)
        }
    }
    
    // MARK: - Logging Methods
    
    /// Logs an error message
    /// - Parameters:
    ///   - message: Message to log
    ///   - file: Source file (automatically included)
    ///   - function: Function name (automatically included)
    ///   - line: Line number (automatically included)
    public static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        if currentLogLevel.rawValue >= LogLevel.error.rawValue {
            let logMessage = "🔴 ERROR: \(formatLogMessage(message, file: file, function: function, line: line))"
            DDLogError(logMessage)
        }
    }
    
    /// Logs a warning message
    /// - Parameters:
    ///   - message: Message to log
    ///   - file: Source file (automatically included)
    ///   - function: Function name (automatically included)
    ///   - line: Line number (automatically included)
    public static func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        if currentLogLevel.rawValue >= LogLevel.warn.rawValue {
            let logMessage = "🟠 WARNING: \(formatLogMessage(message, file: file, function: function, line: line))"
            DDLogWarn(logMessage)
        }
    }
    
    /// Logs an info message
    /// - Parameters:
    ///   - message: Message to log
    ///   - file: Source file (automatically included)
    ///   - function: Function name (automatically included)
    ///   - line: Line number (automatically included)
    public static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        if currentLogLevel.rawValue >= LogLevel.info.rawValue {
            let logMessage = "🔵 INFO: \(formatLogMessage(message, file: file, function: function, line: line))"
            DDLogInfo(logMessage)
        }
    }
    
    /// Logs a debug message
    /// - Parameters:
    ///   - message: Message to log
    ///   - file: Source file (automatically included)
    ///   - function: Function name (automatically included)
    ///   - line: Line number (automatically included)
    public static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        if currentLogLevel.rawValue >= LogLevel.debug.rawValue {
            let logMessage = "⚪️ DEBUG: \(formatLogMessage(message, file: file, function: function, line: line))"
            DDLogDebug(logMessage)
        }
    }
    
    /// Logs a verbose message
    /// - Parameters:
    ///   - message: Message to log
    ///   - file: Source file (automatically included)
    ///   - function: Function name (automatically included)
    ///   - line: Line number (automatically included)
    public static func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        if currentLogLevel.rawValue >= LogLevel.verbose.rawValue {
            let logMessage = "⚪️ VERBOSE: \(formatLogMessage(message, file: file, function: function, line: line))"
            DDLogVerbose(logMessage)
        }
    }
    
    // MARK: - Private Methods
    
    /// Formats a log message with file, function, and line information
    /// - Parameters:
    ///   - message: Message to format
    ///   - file: Source file
    ///   - function: Function name
    ///   - line: Line number
    /// - Returns: Formatted message
    private static func formatLogMessage(_ message: String, file: String, function: String, line: Int) -> String {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        return "[\(fileName):\(line) \(function)] \(message)"
    }
} 