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
        case let .pathTraversal(path):
            "Archive contains unsafe path that escapes target directory: \(path)"
        case let .unsafeSymlink(path, target):
            "Archive contains symlink '\(path)' with unsafe target '\(target)'"
        case let .commandFailed(output):
            "Tar command failed: \(output)"
        }
    }
}

public class Tar {
    static let tarBinary: URL = .init(fileURLWithPath: "/usr/bin/tar")

    public static func tar(folder: URL, toURL: URL) throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        // Archive the folder by name from its parent so the entries are
        // `<folder>/...` rather than the absolute path it happened to live at
        // (which also put the user's home directory name into every export).
        // COPYFILE_DISABLE keeps bsdtar from adding `._` AppleDouble entries.
        process.arguments = [
            "-zcf", toURL.path, "-C", folder.deletingLastPathComponent().path, folder.lastPathComponent
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["COPYFILE_DISABLE"] = "1"
        process.environment = environment
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
    /// Member paths are validated before extraction to prevent "Zip Slip" attacks
    /// where malicious archives contain paths like `../../../etc/passwd` that would
    /// escape the target directory. The archive is then extracted into a staging
    /// directory next to the destination, every symlink in the staged tree is
    /// audited (see ``auditSymlinks(underRoot:)``), and only after both checks pass
    /// is the content moved into place. Nothing from a rejected archive ever
    /// reaches the destination.
    ///
    /// - Parameters:
    ///   - tarBall: The URL to the tarball file to extract.
    ///   - toURL: The destination directory for extraction. Must already exist.
    /// - Throws: `TarError.pathTraversal` if the archive contains unsafe paths,
    ///   `TarError.unsafeSymlink` if a symlink's target escapes the destination,
    ///   `TarError.commandFailed` if the tar command fails, or a `FileManager`
    ///   error if staging or the final move fails.
    public static func untar(tarBall: URL, toURL: URL) throws {
        try validateArchivePaths(tarBall: tarBall, targetDirectory: toURL)

        // Stage next to the destination so the final moves stay on one volume
        // (rename, not copy) and a rejected archive leaves the destination
        // untouched.
        let stagingDir = toURL.deletingLastPathComponent()
            .appending(path: ".untar-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        process.arguments = ["-xzf", "\(tarBall.path)", "-C", "\(stagingDir.path)"]
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

        try auditSymlinks(underRoot: stagingDir)

        try mergeContents(of: stagingDir, into: toURL)
    }

    /// Validates that all paths in a tarball are safe and won't escape the target directory.
    ///
    /// Uses the non-verbose listing (`tar -tzf`): one path per line, with no
    /// metadata columns and no locale-dependent formatting to parse. Symlink
    /// safety — the reason the verbose listing was previously scraped — is
    /// handled by the post-extraction audit in ``untar(tarBall:toURL:)``.
    ///
    /// - Parameters:
    ///   - tarBall: The URL to the tarball file to validate.
    ///   - targetDirectory: The intended extraction directory.
    /// - Throws: `TarError.pathTraversal` if any path would escape the target directory,
    ///   or `TarError.commandFailed` if the listing command fails.
    private static func validateArchivePaths(tarBall: URL, targetDirectory: URL) throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = tarBinary
        process.arguments = ["-tzf", "\(tarBall.path)"]
        // Pin the C locale so bsdtar's escaping of non-printable filename bytes
        // is stable across machines. Escaping can't hide a traversal: `.` and
        // `/` are printable and never escaped, so `..` always appears literally.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Drain the pipe BEFORE waitUntilExit. The listing for a
        // multi-hundred-MB archive easily exceeds the pipe buffer; if we wait
        // for tar to exit first, tar blocks writing while we wait for it to
        // finish and the install hangs forever.
        let output = try pipe.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()

        let listing = String(data: output, encoding: .utf8) ?? ""

        // Ensure the tar listing command succeeded - if it fails, we cannot
        // safely validate the archive contents and must abort extraction
        if process.terminationStatus != 0 {
            throw TarError.commandFailed(output: listing)
        }

        let targetPath = targetDirectory.standardizedFileURL.path
        let lines = listing.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for archivePath in lines {
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
            if resolvedPath != targetPath, !resolvedPath.hasPrefix(normalizedTargetPrefix) {
                throw TarError.pathTraversal(path: archivePath)
            }
        }
    }

    /// Walks an extracted tree and verifies every symlink's target stays inside it.
    ///
    /// This prevents symlink-based path traversal attacks where a malicious archive:
    /// 1. Creates a symlink pointing to a directory outside the target (e.g., `/etc`)
    /// 2. Extracts files "through" that symlink (e.g., `badlink/passwd` → `/etc/passwd`)
    ///
    /// Each link is checked lexically against the root on its own: absolute
    /// targets are rejected outright, and relative targets are resolved from the
    /// link's parent directory. Per-link lexical checks are chain-safe: a chain
    /// of symlinks can only escape the root if some link in the chain has an
    /// escaping target, and that link is rejected when the walk reaches it.
    ///
    /// - Parameter root: The root of the extracted tree to audit.
    /// - Throws: `TarError.unsafeSymlink` if any symlink target escapes `root`.
    static func auditSymlinks(underRoot root: URL) throws {
        let fileManager = FileManager.default
        let rootPath = root.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        )
        else { return }

        for case let item as URL in enumerator {
            let isSymlink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
            guard isSymlink else { continue }

            let itemPath = item.standardizedFileURL.path
            let relativePath = itemPath.hasPrefix(rootPrefix)
                ? String(itemPath.dropFirst(rootPrefix.count))
                : itemPath
            let target = try fileManager.destinationOfSymbolicLink(
                atPath: item.path(percentEncoded: false)
            )

            // Absolute targets always escape
            if target.hasPrefix("/") {
                throw TarError.unsafeSymlink(path: relativePath, target: target)
            }

            // Resolve the target lexically from the symlink's parent directory
            let resolvedPath = item.deletingLastPathComponent()
                .appendingPathComponent(target).standardizedFileURL.path

            if resolvedPath != rootPath, !resolvedPath.hasPrefix(rootPrefix) {
                throw TarError.unsafeSymlink(path: relativePath, target: target)
            }
        }
    }

    /// Moves every entry of `source` into `destination`, merging directories and
    /// replacing existing files — mirroring `tar -x` overwrite semantics so
    /// staged extraction behaves like the direct extraction it replaced.
    private static func mergeContents(of source: URL, into destination: URL) throws {
        let fileManager = FileManager.default

        for name in try fileManager.contentsOfDirectory(atPath: source.path(percentEncoded: false)) {
            let staged = source.appending(path: name)
            let target = destination.appending(path: name)

            // attributesOfItem does not follow symlinks, so a staged link to a
            // directory is moved as a link, never merged as a directory.
            let stagedType = try fileManager.attributesOfItem(
                atPath: staged.path(percentEncoded: false)
            )[.type] as? FileAttributeType
            let targetType = (try? fileManager.attributesOfItem(
                atPath: target.path(percentEncoded: false)
            ))?[.type] as? FileAttributeType

            if stagedType == .typeDirectory, targetType == .typeDirectory {
                try mergeContents(of: staged, into: target)
            } else {
                if targetType != nil {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.moveItem(at: staged, to: target)
            }
        }
    }
}

extension String: @retroactive Error {}
