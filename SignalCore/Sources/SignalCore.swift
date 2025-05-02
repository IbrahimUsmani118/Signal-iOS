/*
 * Copyright (C) 2025 Open Whisper Systems
 *
 * This file is part of Signal.
 *
 * Signal is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License version 3
 * as published by the Free Software Foundation.
 *
 * Signal is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with Signal. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import os

/// Placeholder implementation for SignalCore module.
/// Provides basic utilities and ensures Swift Package Manager compatibility.
public struct SignalCore {
    private init() { }

    /// Logs a debug message using OSLog.
    /// - Parameter message: The message to log.
    public static func logDebug(_ message: String) {
        if #available(iOS 14.0, *) {
            os_log(.debug, "[SignalCore] %{public}@", message)
        } else {
            print("[SignalCore DEBUG] \(message)")
        }
    }

    /// Logs an error message with optional associated error.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - error: An optional Error to include in the log.
    public static func logError(_ message: String, error: Error? = nil) {
        if #available(iOS 14.0, *) {
            if let error = error {
                os_log(.error, "[SignalCore] %{public}@ - Error: %{public}@", message, String(describing: error))
            } else {
                os_log(.error, "[SignalCore] %{public}@", message)
            }
        } else {
            if let error = error {
                print("[SignalCore ERROR] \(message) - Error: \(error)")
            } else {
                print("[SignalCore ERROR] \(message)")
            }
        }
    }
}

// MARK: - String Utilities

public extension String {
    /// Returns a reversed copy of the string.
    /// - Returns: A new string containing the characters of the original string in reverse order.
    func reversedString() -> String {
        return String(self.reversed())
    }

    /// Checks if the string contains only hexadecimal characters (0-9, a-f, A-F).
    var isHexadecimal: Bool {
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return !self.isEmpty && self.unicodeScalars.allSatisfy { hexSet.contains($0) }
    }
}
