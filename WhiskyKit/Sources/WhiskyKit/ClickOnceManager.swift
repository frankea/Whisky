//
//  ClickOnceManager.swift
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

// swiftlint:disable file_length

import Foundation
import os.log

/// Manager for ClickOnce application detection and installation.
///
/// This singleton provides methods to detect ClickOnce applications within Wine bottles,
/// parse their manifests, and generate appropriate environment variables for execution.
/// ClickOnce is a Microsoft deployment technology that uses `.appref-ms` files as
/// application references.
///
/// ## Usage
///
/// ```swift
/// // Detect ClickOnce apps in a bottle
/// let appRefs = ClickOnceManager.shared.detectAppRefFile(in: bottle)
///
/// // Parse manifest from appref-ms file
/// let manifest = try ClickOnceManager.shared.parseManifest(from: appRefURL)
///
/// // Get environment variables for ClickOnce app
/// let env = ClickOnceManager.shared.getEnvironment(for: manifest)
/// ```
public final class ClickOnceManager: @unchecked Sendable {
    public static let shared = ClickOnceManager()

    private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ClickOnceManager")

    /// Information extracted from a ClickOnce manifest.
    public struct ClickOnceManifest: Sendable {
        /// Application name
        public let name: String
        /// URL to the application executable
        public let url: URL
        /// Application version
        public let version: String
        /// Publisher name
        public let publisher: String
        /// Optional support URL
        public let supportUrl: URL?
        /// Optional description
        public let description: String?
    }

    private init() {}

    /// Resolves the Wine username for a bottle, preferring the actual user
    /// directory found in `drive_c/users/` and falling back to "crossover".
    private static func resolveWineUsername(for bottle: Bottle) -> String {
        let usersDir = bottle.url.appending(path: "drive_c").appending(path: "users")
        return WinePrefixValidation.detectWineUsername(in: usersDir) ?? "crossover"
    }

    // MARK: - Detection

    /// Detects ClickOnce application reference files in a bottle.
    ///
    /// This method scans the standard ClickOnce installation directory within
    /// the Wine bottle for `.appref-ms` files.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to scan for ClickOnce apps
    ///   - wineUsername: The Wine username for path construction. When `nil`
    ///     the username is auto-detected from the bottle's `drive_c/users`
    ///     directory (falling back to "crossover").
    /// - Returns: Array of URLs to detected `.appref-ms` files
    public func detectAppRefFile(in bottle: Bottle, wineUsername: String? = nil) -> [URL] {
        let resolvedUsername = wineUsername ?? Self.resolveWineUsername(for: bottle)
        let clickOnceDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: resolvedUsername)
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "ClickOnce")

        guard FileManager.default.fileExists(atPath: clickOnceDir.path) else {
            logger.debug("ClickOnce directory not found: \(clickOnceDir.path)")
            return []
        }

        var appRefFiles: [URL] = []

        // Recursively scan for .appref-ms files
        if let enumerator = FileManager.default.enumerator(at: clickOnceDir, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "appref-ms" {
                    appRefFiles.append(fileURL)
                    logger.debug("Found ClickOnce appref: \(fileURL.lastPathComponent)")
                }
            }
        }

        logger
            .info("Detected \(appRefFiles.count) ClickOnce application(s) in bottle '\(bottle.url.lastPathComponent)'")
        return appRefFiles
    }

    // MARK: - Parsing

    /// Parses a ClickOnce manifest from an `.appref-ms` file.
    ///
    /// The `.appref-ms` file is a small text file (similar to a Windows Internet Shortcut)
    /// that typically contains a `URL=` line pointing at a ClickOnce deployment URL.
    ///
    /// - Parameter url: URL to the `.appref-ms` file
    /// - Returns: Parsed ClickOnceManifest
    /// - Throws: Error if file cannot be read or parsed
    public func parseManifest(from url: URL) throws -> ClickOnceManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ClickOnceError.fileNotFound(url)
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        return try parseManifestContent(content, fileURL: url)
    }

    /// Parses ClickOnce manifest content from a string.
    ///
    /// - Parameters:
    ///   - content: Content of the `.appref-ms` file
    ///   - fileURL: URL of the source file (for error reporting)
    /// - Returns: Parsed ClickOnceManifest
    /// - Throws: Error if content cannot be parsed
    private func parseManifestContent(_ content: String, fileURL: URL) throws -> ClickOnceManifest {
        // .appref-ms files are typically INI-like:
        // [InternetShortcut]
        // URL=<url or percent-encoded url>

        let fallbackName = fileURL.deletingPathExtension().lastPathComponent
        let rawURLString = try extractURLString(from: content)
        let urlString = normalizeURLString(rawURLString)

        guard let url = URL(string: urlString) else {
            throw ClickOnceError.invalidManifest("Invalid URL in appref-ms file: \(urlString)")
        }

        let name = url.lastPathComponent.isEmpty ? fallbackName : url.lastPathComponent
        let version = extractVersion(from: url) ?? "1.0.0.0"
        let publisher = "Unknown"
        let supportUrl: URL? = nil
        let description: String? = nil

        logger.debug("Parsed ClickOnce manifest: \(name) v\(version)")

        return ClickOnceManifest(
            name: name,
            url: url,
            version: version,
            publisher: publisher,
            supportUrl: supportUrl,
            description: description
        )
    }

    private func extractURLString(from content: String) throws -> String {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4 else { continue }

            let prefix = trimmed.prefix(4).lowercased()
            guard prefix == "url=" else { continue }

            let value = trimmed.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return String(value)
        }

        throw ClickOnceError.invalidManifest("No URL found in appref-ms file")
    }

    private func normalizeURLString(_ rawURLString: String) -> String {
        // Many `.appref-ms` files contain a plain URL, but some include a percent-encoded URL
        // (and a few are doubly-encoded). Decode conservatively and only apply the second
        // decode when it results in a valid URL.
        let decodedOnce = rawURLString.removingPercentEncoding ?? rawURLString
        if URL(string: decodedOnce) != nil {
            return decodedOnce
        }

        let decodedTwice = decodedOnce.removingPercentEncoding ?? decodedOnce
        if URL(string: decodedTwice) != nil {
            return decodedTwice
        }

        return decodedOnce
    }

    private func extractVersion(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { item in
            item.name == "version" || item.name == "v"
        })?.value
    }

    // MARK: - Display Helpers

    /// Returns a user-friendly display name for a ClickOnce application reference file.
    ///
    /// This method tries to parse the `.appref-ms` file and extract a friendly name
    /// from the manifest URL. It strips the `.appref-ms` extension and any trailing
    /// `.application` suffix from the URL's last path component.
    ///
    /// - Parameter appRefURL: URL to the `.appref-ms` file
    /// - Returns: A friendly display name string
    public func displayName(for appRefURL: URL) -> String {
        let fallbackName = appRefURL.deletingPathExtension().lastPathComponent

        do {
            let manifest = try parseManifest(from: appRefURL)
            var name = manifest.url.lastPathComponent
            // Strip trailing .application extension if present
            if name.hasSuffix(".application") {
                name = String(name.dropLast(".application".count))
            }
            return name.isEmpty ? fallbackName : name
        } catch {
            return fallbackName
        }
    }

    /// Returns the deployment URL from a ClickOnce application reference file.
    ///
    /// This method reads and parses the `.appref-ms` file to extract the
    /// deployment URL from the manifest.
    ///
    /// - Parameter appRefURL: URL to the `.appref-ms` file
    /// - Returns: The deployment URL, or nil if parsing fails
    public func deploymentURL(for appRefURL: URL) -> URL? {
        do {
            let manifest = try parseManifest(from: appRefURL)
            return manifest.url
        } catch {
            logger.debug("Failed to extract deployment URL from \(appRefURL.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Environment

    /// Generates environment variables for a ClickOnce application.
    ///
    /// This method creates the standard ClickOnce environment variables that
    /// Wine applications expect when running ClickOnce deployments.
    ///
    /// - Parameter manifest: The ClickOnce manifest
    /// - Returns: Dictionary of environment variables
    public func getEnvironment(for manifest: ClickOnceManifest) -> [String: String] {
        var env = [String: String]()

        env["CLICKONCE_APP"] = manifest.name
        env["CLICKONCE_VERSION"] = manifest.version
        env["CLICKONCE_PUBLISHER"] = manifest.publisher

        if let supportUrl = manifest.supportUrl {
            env["CLICKONCE_SUPPORT_URL"] = supportUrl.absoluteString
        }

        if let description = manifest.description {
            env["CLICKONCE_DESCRIPTION"] = description
        }

        logger.debug("Generated ClickOnce environment for '\(manifest.name)'")
        return env
    }

    /// Installs a ClickOnce application in a bottle.
    ///
    /// This method materializes an `.appref-ms` reference file inside the bottle's
    /// ClickOnce directory. This enables later detection via ``detectAppRefFile(in:wineUsername:)``.
    ///
    /// - Parameters:
    ///   - manifest: The ClickOnce manifest to install
    ///   - bottle: The bottle to install into
    ///   - wineUsername: The Wine username for path construction. When `nil`
    ///     the username is auto-detected from the bottle's `drive_c/users`
    ///     directory (falling back to "crossover").
    /// - Throws: Error if installation fails
    public func install(
        manifest: ClickOnceManifest,
        in bottle: Bottle,
        wineUsername: String? = nil
    ) async throws {
        guard validateManifest(manifest) else {
            throw ClickOnceError.installationFailed("Manifest failed validation")
        }

        let bottleName = bottle.url.lastPathComponent
        logger.info("Installing ClickOnce app '\(manifest.name)' v\(manifest.version) in bottle '\(bottleName)'")

        let resolvedUsername = wineUsername ?? Self.resolveWineUsername(for: bottle)
        let clickOnceDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: resolvedUsername)
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "ClickOnce")

        do {
            try FileManager.default.createDirectory(at: clickOnceDir, withIntermediateDirectories: true)

            // Ensure a stable filename on disk.
            let fileNameBase = manifest.name
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            let appRefURL = clickOnceDir
                .appending(path: fileNameBase.isEmpty ? "ClickOnceApp" : fileNameBase)
                .appendingPathExtension("appref-ms")

            let content = """
            [InternetShortcut]
            URL=\(manifest.url.absoluteString)
            """

            try content.write(to: appRefURL, atomically: true, encoding: .utf8)
            logger.debug("Wrote ClickOnce appref-ms: \(appRefURL.path)")
        } catch {
            throw ClickOnceError.installationFailed(error.localizedDescription)
        }

        logger.info("ClickOnce app '\(manifest.name)' installed successfully")
    }

    /// Validates a ClickOnce manifest.
    ///
    /// This method checks if a manifest contains all required fields
    /// and is properly formatted.
    ///
    /// - Parameter manifest: The manifest to validate
    /// - Returns: true if valid, false otherwise
    public func validateManifest(_ manifest: ClickOnceManifest) -> Bool {
        // Check required fields
        if manifest.name.isEmpty {
            logger.warning("ClickOnce manifest validation failed: empty name")
            return false
        }

        if manifest.version.isEmpty {
            logger.warning("ClickOnce manifest validation failed: empty version")
            return false
        }

        if manifest.publisher.isEmpty {
            logger.warning("ClickOnce manifest validation failed: empty publisher")
            return false
        }

        // Validate version format (should be semantic version)
        let versionPattern = "^\\d+\\.\\d+\\.\\d+\\.\\d+$"
        if manifest.version.range(of: versionPattern, options: .regularExpression) == nil {
            logger.debug("ClickOnce manifest has non-standard version format: \(manifest.version)")
        }

        logger.debug("ClickOnce manifest '\(manifest.name)' is valid")
        return true
    }
}

// MARK: - Errors

/// Errors that can occur during ClickOnce operations.
public enum ClickOnceError: LocalizedError {
    case fileNotFound(URL)
    case invalidManifest(String)
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(url):
            "ClickOnce file not found: \(url.path)"
        case let .invalidManifest(message):
            "Invalid ClickOnce manifest: \(message)"
        case let .installationFailed(message):
            "ClickOnce installation failed: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            "Ensure the ClickOnce application is properly installed in the bottle."
        case .invalidManifest:
            "Verify the .appref-ms file is not corrupted."
        case .installationFailed:
            "Check Wine logs for more details and try reinstalling the application."
        }
    }
}
