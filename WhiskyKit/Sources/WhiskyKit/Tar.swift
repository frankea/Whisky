//
//  Tar.swift
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

/// Errors that can occur during tar operations.
public enum TarError: LocalizedError {
    /// The archive contains paths that would escape the target directory.
    case pathTraversal(path: String)
    /// The archive contains a symlink with an unsafe target.
    case unsafeSymlink(path: String, target: String)
    /// The tar command failed with the given output.
    case commandFailed(output: String)

    public var errorDescription: String? {
        switch self {
        case .pathTraversal(let path):
            return "Archive contains unsafe path that escapes target directory: \(path)"
        case .unsafeSymlink(let path, let target):
            return "Archive contains symlink '\(path)' with unsafe target '\(target)'"
        case .commandFailed(let output):
            return "Tar command failed: \(output)"
        }
    }
}

public class Tar {
    static let tarBinary: URL = URL(fileURLWithPath: "/usr/bin/tar")

    public static func tar(folder: URL, toURL: URL) throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        process.arguments = ["-zcf", "\(toURL.path)", "\(folder.path)"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        if let output = try pipe.fileHandleForReading.readToEnd() {
            let outputString = String(data: output, encoding: .utf8) ?? String()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                throw TarError.commandFailed(output: outputString)
            }
        }
    }

    /// Extracts a tarball to the specified directory with path traversal protection.
    ///
    /// This method validates all paths in the archive before extraction to prevent
    /// "Zip Slip" attacks where malicious archives contain paths like `../../../etc/passwd`
    /// that would escape the target directory.
    ///
    /// - Parameters:
    ///   - tarBall: The URL to the tarball file to extract.
    ///   - toURL: The destination directory for extraction.
    /// - Throws: `TarError.pathTraversal` if the archive contains unsafe paths,
    ///   or `TarError.commandFailed` if the tar command fails.
    public static func untar(tarBall: URL, toURL: URL) throws {
        // First, validate archive contents for path traversal attacks
        try validateArchivePaths(tarBall: tarBall, targetDirectory: toURL)

        // Safe to extract after validation
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        process.arguments = ["-xzf", "\(tarBall.path)", "-C", "\(toURL.path)"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        if let output = try pipe.fileHandleForReading.readToEnd() {
            let outputString = String(data: output, encoding: .utf8) ?? String()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                throw TarError.commandFailed(output: outputString)
            }
        }
    }

    /// Validates that all paths in a tarball are safe and won't escape the target directory.
    ///
    /// This method also validates symlinks to prevent symlink-based path traversal attacks
    /// where a malicious archive creates a symlink pointing outside the target directory,
    /// then writes files through that symlink.
    ///
    /// - Parameters:
    ///   - tarBall: The URL to the tarball file to validate.
    ///   - targetDirectory: The intended extraction directory.
    /// - Throws: `TarError.pathTraversal` if any path would escape the target directory,
    ///   or `TarError.unsafeSymlink` if a symlink target would escape the target directory.
    private static func validateArchivePaths(tarBall: URL, targetDirectory: URL) throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        // Use verbose listing to see file types and symlink targets
        // Format: "lrwxr-xr-x  0 user group    0 Jan 10 12:00 linkname -> target"
        process.arguments = ["-tvzf", "\(tarBall.path)"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = try pipe.fileHandleForReading.readToEnd() ?? Data()
        let listing = String(data: output, encoding: .utf8) ?? ""

        // Ensure the tar listing command succeeded - if it fails, we cannot
        // safely validate the archive contents and must abort extraction
        if process.terminationStatus != 0 {
            throw TarError.commandFailed(output: listing)
        }

        let targetPath = targetDirectory.standardizedFileURL.path
        let lines = listing.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse the archive entry - extract file path and check for symlinks
            let (archivePath, symlinkTarget) = parseVerboseTarLine(trimmed)

            guard !archivePath.isEmpty else { continue }

            // Check for absolute paths
            if archivePath.hasPrefix("/") {
                throw TarError.pathTraversal(path: archivePath)
            }

            // Check for path traversal sequences (fast rejection for obvious cases)
            // Note: The resolved path check below is the authoritative security boundary
            if archivePath.contains("../") || archivePath.hasPrefix("..") {
                throw TarError.pathTraversal(path: archivePath)
            }

            // Resolve the full path and verify it stays within target directory
            let resolvedURL = targetDirectory.appendingPathComponent(archivePath).standardizedFileURL
            let resolvedPath = resolvedURL.path

            // Ensure that the target directory path ends with a separator so that we
            // only treat true subpaths as inside the directory (and not siblings like
            // "/foo/bar-malicious" when targetPath is "/foo/bar").
            let normalizedTargetPrefix = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"

            // The resolved path must either be exactly the directory itself or a proper subpath
            if resolvedPath != targetPath && !resolvedPath.hasPrefix(normalizedTargetPrefix) {
                throw TarError.pathTraversal(path: archivePath)
            }

            // Validate symlink targets to prevent symlink-based path traversal
            if let target = symlinkTarget {
                try validateSymlinkTarget(
                    symlinkPath: archivePath,
                    target: target,
                    targetDirectory: targetDirectory
                )
            }
        }
    }

    /// Parses a verbose tar listing line to extract the file path and symlink target (if any).
    ///
    /// Verbose tar output format:
    /// - Regular file: "-rw-r--r--  0 user group  1234 Jan 10 12:00 path/to/file"
    /// - Directory:    "drwxr-xr-x  0 user group     0 Jan 10 12:00 path/to/dir/"
    /// - Symlink:      "lrwxr-xr-x  0 user group     0 Jan 10 12:00 linkname -> target"
    ///
    /// - Note: If parsing fails (e.g., due to locale differences or unexpected formats),
    ///   this method returns a synthetic path containing `../` that will trigger path traversal
    ///   detection. This ensures archives with unparseable entries are rejected rather than
    ///   having those entries silently skipped, which could allow malicious paths through.
    ///
    /// - Parameter line: A line from `tar -tvzf` output.
    /// - Returns: A tuple of (archivePath, symlinkTarget) where symlinkTarget is nil for non-symlinks.
    private static func parseVerboseTarLine(_ line: String) -> (path: String, symlinkTarget: String?) {
        // Check if this is a symlink (line starts with 'l')
        let isSymlink = line.hasPrefix("l")

        if isSymlink, let arrowRange = line.range(of: " -> ") {
            // Extract symlink path (before " -> ") and target (after " -> ")
            let beforeArrow = String(line[..<arrowRange.lowerBound])
            let target = String(line[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            // The path is the last whitespace-separated component before " -> "
            // We need to find where the path starts after the metadata columns
            if let path = extractPathFromTarLine(beforeArrow) {
                return (path, target)
            }
            // If we cannot parse the path from this line, treat it as an unsafe entry.
            // Returning a synthetic path that will be detected as a traversal attempt
            // ensures the archive is rejected rather than silently skipping validation.
            return ("../__TAR_PARSE_ERROR__", target)
        } else {
            // Regular file or directory - extract path from the line
            if let path = extractPathFromTarLine(line) {
                return (path, nil)
            }
            // If we cannot parse the path from this line, treat it as an unsafe entry.
            // Returning a synthetic path that will be detected as a traversal attempt
            // ensures the archive is rejected rather than silently skipping validation.
            return ("../__TAR_PARSE_ERROR__", nil)
        }
    }

    /// Extracts the file path from a tar verbose listing line.
    ///
    /// The format has variable-width columns, so we find the path by looking for
    /// the timestamp pattern and taking everything after it.
    ///
    /// - Parameter line: A line or partial line from `tar -tvzf` output.
    /// - Returns: The extracted file path, or nil if parsing fails.
    private static func extractPathFromTarLine(_ line: String) -> String? {
        // Tar verbose format: "perms links user group size month day time/year path"
        // macOS BSD tar uses two timestamp formats:
        // - Recent files (< ~6 months): "Jan 10 12:00" (month day time)
        // - Older files (> ~6 months):  "Dec  4  2015" (month day year)
        //
        // Examples:
        // "-rw-r--r--  0 user group  1234 Jan 10 12:00 path/to/file"
        // "-rw-r--r--  0 user group  1234 Dec  4  2015 path/to/old/file"

        // Pattern: month (3 chars) + space + day (1-2 digits) + space + (time OR year) + space + path
        // Time format: HH:MM or HH:MM:SS (e.g., "12:00" or "12:00:00")
        // Year format: YYYY (e.g., "2015")
        let pattern = #"[A-Za-z]{3}\s+\d{1,2}\s+(?:\d{1,2}:\d{2}(?::\d{2})?|\d{4})\s+(.+)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                in: line,
                options: [],
                range: NSRange(line.startIndex..., in: line)
              ),
              let pathRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        return String(line[pathRange]).trimmingCharacters(in: .whitespaces)
    }

    /// Validates that a symlink target is safe and won't allow escaping the target directory.
    ///
    /// This prevents symlink-based path traversal attacks where a malicious archive:
    /// 1. Creates a symlink pointing to a directory outside the target (e.g., `/etc`)
    /// 2. Extracts files "through" that symlink (e.g., `badlink/passwd` → `/etc/passwd`)
    ///
    /// - Parameters:
    ///   - symlinkPath: The path of the symlink within the archive.
    ///   - target: The symlink's target path.
    ///   - targetDirectory: The extraction target directory.
    /// - Throws: `TarError.unsafeSymlink` if the symlink target would escape the target directory.
    private static func validateSymlinkTarget(
        symlinkPath: String,
        target: String,
        targetDirectory: URL
    ) throws {
        // Reject absolute symlink targets - these always escape
        if target.hasPrefix("/") {
            throw TarError.unsafeSymlink(path: symlinkPath, target: target)
        }

        // For relative symlink targets, resolve from the symlink's parent directory
        // E.g., if symlink is "foo/bar/link" with target "../../../etc",
        // resolve from "foo/bar/" to check if it escapes

        let symlinkURL = targetDirectory.appendingPathComponent(symlinkPath)
        let symlinkParent = symlinkURL.deletingLastPathComponent()

        // Resolve the target relative to the symlink's location
        let resolvedTarget = symlinkParent.appendingPathComponent(target).standardizedFileURL
        let resolvedPath = resolvedTarget.path
        let targetPath = targetDirectory.standardizedFileURL.path

        // Ensure that the target directory path ends with a separator so that we
        // only treat true subpaths as inside the directory (and not siblings like
        // "/foo/bar-malicious" when targetPath is "/foo/bar").
        let normalizedTargetPrefix = targetPath.hasSuffix("/") ? targetPath : targetPath + "/"

        // Check if the resolved symlink target stays within the target directory:
        // it must either be exactly the directory itself or a proper subpath.
        if resolvedPath != targetPath && !resolvedPath.hasPrefix(normalizedTargetPrefix) {
            throw TarError.unsafeSymlink(path: symlinkPath, target: target)
        }
    }
}

extension String: @retroactive Error {}
