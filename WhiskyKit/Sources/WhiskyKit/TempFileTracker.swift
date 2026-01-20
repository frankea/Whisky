//
//  TempFileTracker.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import os.log

/// Tracker for temporary files created by Whisky.
///
/// This singleton maintains a registry of temporary files with retry mechanisms
/// for cleanup, handling locked files and permission issues gracefully.
/// It supports periodic cleanup of old files and integration with process cleanup.
///
/// ## Usage
///
/// ```swift
/// // Register a temp file when creating it
/// TempFileTracker.shared.register(file: tempScriptURL)
///
/// // Clean up with retry mechanism
/// await TempFileTracker.shared.cleanupWithRetry(file: tempScriptURL, maxRetries: 3)
///
/// // Clean up old files periodically
/// await TempFileTracker.shared.cleanupOldFiles(olderThan: 24 * 60 * 60) // 24 hours
/// ```
public final class TempFileTracker: @unchecked Sendable {
    static let shared = TempFileTracker()

    private let lock = NSLock()
    private var tempFiles: [URL: TempFileInfo] = [:]

    private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "TempFileTracker")

    /// Information about a tracked temporary file.
    public struct TempFileInfo: Hashable, Sendable {
        /// URL of the temporary file
        public let url: URL
        /// When the file was created
        public let creationTime: Date
        /// PID of associated process (if any)
        public let associatedProcess: Int32?
        /// Number of cleanup attempts made
        public var cleanupAttempts: Int
        /// Maximum retry attempts
        public let maxRetries: Int

        public func hash(into hasher: inout Hasher) {
            hasher.combine(url)
            hasher.combine(creationTime)
            hasher.combine(associatedProcess)
        }

        public static func == (lhs: TempFileInfo, rhs: TempFileInfo) -> Bool {
            lhs.url == rhs.url &&
                lhs.creationTime == rhs.creationTime &&
                lhs.associatedProcess == rhs.associatedProcess
        }
    }

    private init() {}

    // MARK: - Registration

    /// Registers a temporary file for tracking.
    ///
    /// This method should be called when creating a temporary file.
    ///
    /// - Parameters:
    ///   - file: URL of the temporary file to track
    ///   - process: Optional PID of the associated process
    public func register(file: URL, process: Int32? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let info = TempFileInfo(
            url: file,
            creationTime: Date(),
            associatedProcess: process,
            cleanupAttempts: 0,
            maxRetries: 3 // Default max retries
        )

        tempFiles[file] = info

        logger.debug("Registered temp file '\(file.lastPathComponent)'")
    }

    /// Marks a file for cleanup (increments attempt counter).
    ///
    /// This is called before each cleanup attempt.
    ///
    /// - Parameter file: URL of the file to mark for cleanup
    public func markForCleanup(file: URL) {
        lock.lock()
        defer { lock.unlock() }

        guard var info = tempFiles[file] else {
            logger.warning("File not registered for cleanup: \(file.path)")
            return
        }

        info.cleanupAttempts += 1
        tempFiles[file] = info

        logger.debug("Marked '\(file.lastPathComponent)' for cleanup (attempt \(info.cleanupAttempts))")
    }

    // MARK: - Cleanup

    /// Cleans up a temporary file with retry mechanism.
    ///
    /// This method attempts to delete a file multiple times with exponential backoff.
    /// It checks if the file is locked before each attempt.
    ///
    /// - Parameters:
    ///   - file: URL of the file to delete
    ///   - maxRetries: Maximum number of cleanup attempts (default: 3)
    public func cleanupWithRetry(file: URL, maxRetries: Int = 3) async {
        for attempt in 0 ..< maxRetries {
            // Check if file is locked
            if isFileLocked(file) {
                logger.warning("File '\(file.lastPathComponent)' is locked, attempt \(attempt + 1)/\(maxRetries)")

                if attempt < maxRetries - 1 {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = TimeInterval(pow(2.0, Double(attempt)))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    logger
                        .error(
                            "Failed to cleanup '\(file.lastPathComponent)' after \(maxRetries) attempts (file locked)"
                        )
                    removeFromRegistry(file)
                    return
                }
            }

            // Attempt deletion
            do {
                try FileManager.default.removeItem(at: file)
                removeFromRegistry(file)
                logger.info("Successfully cleaned up '\(file.lastPathComponent)' (attempt \(attempt + 1))")
                return
            } catch {
                let fileName = file.lastPathComponent
                let errorDesc = error.localizedDescription
                logger.warning("Cleanup attempt \(attempt + 1) failed for '\(fileName)': \(errorDesc)")

                if attempt < maxRetries - 1 {
                    // Exponential backoff
                    let delay = TimeInterval(pow(2.0, Double(attempt)))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    logger.error("Failed to cleanup '\(fileName)' after \(maxRetries) attempts: \(errorDesc)")
                    removeFromRegistry(file)
                    return
                }
            }
        }
    }

    /// Cleans up all temporary files associated with a specific process.
    ///
    /// This is called when a process terminates.
    ///
    /// - Parameter process: PID of the process whose temp files should be cleaned
    public func cleanup(associatedWith process: Int32) {
        lock.lock()
        defer { lock.unlock() }

        let filesToCleanup = tempFiles.filter { $0.value.associatedProcess == process }

        for (file, _) in filesToCleanup {
            logger.info("Cleaning up temp file '\(file.lastPathComponent)' associated with process \(process)")
            Task {
                await cleanupWithRetry(file: file)
            }
        }
    }

    /// Cleans up all temporary files.
    ///
    /// This method attempts to clean up all tracked temp files.
    public func cleanupAll() {
        lock.lock()
        let allFiles = Array(tempFiles.keys)
        lock.unlock()

        logger.info("Cleaning up \(allFiles.count) temporary file(s)")

        Task {
            for file in allFiles {
                await cleanupWithRetry(file: file)
            }
        }
    }

    /// Cleans up temporary files older than a specified age.
    ///
    /// This is useful for periodic cleanup of orphaned temp files.
    ///
    /// - Parameter olderThan: Age in seconds (files older than this will be deleted)
    public func cleanupOldFiles(olderThan seconds: TimeInterval) async {
        let cutoffDate = Date().addingTimeInterval(-seconds)
        let oldFileURLs = getOldFiles(olderThan: cutoffDate)

        guard !oldFileURLs.isEmpty else {
            logger.debug("No old temp files to clean up")
            return
        }

        logger.info("Cleaning up \(oldFileURLs.count) old temp file(s) (older than \(seconds) seconds)")

        for file in oldFileURLs {
            do {
                try FileManager.default.removeItem(at: file)
                removeFromRegistry(file)
                logger.debug("Cleaned up old temp file '\(file.lastPathComponent)'")
            } catch {
                logger
                    .warning(
                        "Failed to cleanup old temp file '\(file.lastPathComponent)': \(error.localizedDescription)"
                    )
            }
        }
    }

    // MARK: - File Lock Detection

    /// Checks if a file is locked (in use).
    ///
    /// This method attempts to open the file for exclusive write access.
    /// If successful, the file is not locked.
    ///
    /// - Parameter file: URL of the file to check
    /// - Returns: true if the file is locked, false otherwise
    private func isFileLocked(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false // File doesn't exist, not locked
        }

        // Try to open for exclusive write access
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.close()
            return false // Successfully opened, not locked
        } catch {
            // Failed to open, likely locked
            logger.debug("File '\(url.lastPathComponent)' appears to be locked: \(error.localizedDescription)")
            return true
        }
    }

    // MARK: - Querying

    /// Returns all tracked temporary files.
    ///
    /// - Returns: Dictionary mapping file URLs to their info
    public func getAllTrackedFiles() -> [URL: TempFileInfo] {
        lock.lock()
        defer { lock.unlock() }
        return tempFiles
    }

    /// Returns the count of tracked temporary files.
    ///
    /// - Returns: Number of tracked temp files
    public func getTrackedFileCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return tempFiles.count
    }

    // MARK: - Private Helpers (Synchronous)

    /// Removes a file from the registry (synchronous, for use from async contexts).
    private func removeFromRegistry(_ file: URL) {
        lock.lock()
        tempFiles.removeValue(forKey: file)
        lock.unlock()
    }

    /// Gets old files older than the specified date (synchronous, for use from async contexts).
    private func getOldFiles(olderThan cutoffDate: Date) -> [URL] {
        lock.lock()
        let oldFiles = tempFiles.filter { $0.value.creationTime < cutoffDate }
        let result = Array(oldFiles.keys)
        lock.unlock()
        return result
    }

    // MARK: - Testing Support

    /// Resets the tracker to empty state. For testing purposes only.
    public func reset() {
        lock.lock()
        tempFiles.removeAll()
        lock.unlock()
    }
}
