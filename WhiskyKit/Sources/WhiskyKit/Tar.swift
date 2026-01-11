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
    /// The tar command failed with the given output.
    case commandFailed(output: String)

    public var errorDescription: String? {
        switch self {
        case .pathTraversal(let path):
            return "Archive contains unsafe path that escapes target directory: \(path)"
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
    /// - Parameters:
    ///   - tarBall: The URL to the tarball file to validate.
    ///   - targetDirectory: The intended extraction directory.
    /// - Throws: `TarError.pathTraversal` if any path would escape the target directory.
    private static func validateArchivePaths(tarBall: URL, targetDirectory: URL) throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        // List archive contents without extracting
        process.arguments = ["-tzf", "\(tarBall.path)"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard let output = try pipe.fileHandleForReading.readToEnd(),
              let listing = String(data: output, encoding: .utf8) else {
            return
        }

        let targetPath = targetDirectory.standardizedFileURL.path
        let paths = listing.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for archivePath in paths {
            // Check for absolute paths
            if archivePath.hasPrefix("/") {
                throw TarError.pathTraversal(path: archivePath)
            }

            // Check for path traversal sequences
            if archivePath.contains("../") || archivePath.hasPrefix("..") {
                throw TarError.pathTraversal(path: archivePath)
            }

            // Resolve the full path and verify it stays within target directory
            let resolvedURL = targetDirectory.appendingPathComponent(archivePath).standardizedFileURL
            let resolvedPath = resolvedURL.path

            if !resolvedPath.hasPrefix(targetPath) {
                throw TarError.pathTraversal(path: archivePath)
            }
        }
    }
}

extension String: @retroactive Error {}
