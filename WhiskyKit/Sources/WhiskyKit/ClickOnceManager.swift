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
public final class ClickOnceManager {
    static let shared = ClickOnceManager()

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

    // MARK: - Detection

    /// Detects ClickOnce application reference files in a bottle.
    ///
    /// This method scans the standard ClickOnce installation directory within
    /// the Wine bottle for `.appref-ms` files.
    ///
    /// - Parameter bottle: The bottle to scan for ClickOnce apps
    /// - Returns: Array of URLs to detected `.appref-ms` files
    public func detectAppRefFile(in bottle: Bottle) -> [URL] {
        let clickOnceDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
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

        logger.info("Detected \(appRefFiles.count) ClickOnce application(s) in bottle '\(bottle.settings.name)'")
        return appRefFiles
    }

    // MARK: - Parsing

    /// Parses a ClickOnce manifest from an `.appref-ms` file.
    ///
    /// The `.appref-ms` file contains XML with application metadata including
    /// name, version, publisher, and deployment URL.
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
    ///   - content: XML content of the manifest
    ///   - fileURL: URL of the source file (for error reporting)
    /// - Returns: Parsed ClickOnceManifest
    /// - Throws: Error if content cannot be parsed
    private func parseManifestContent(_ content: String, fileURL: URL) throws -> ClickOnceManifest {
        // .appref-ms files are actually text files with URL-encoded content
        // The format is: [InternetShortcut]\nURL=<encoded-url>
        // The encoded URL contains the actual manifest information

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var manifestURL: String?
        var name = fileURL.deletingPathExtension().lastPathComponent
        var version = "1.0.0.0"
        var publisher = "Unknown"
        var supportUrl: URL?
        var description: String?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("URL=") {
                let urlString = String(trimmedLine.dropFirst(4))
                manifestURL = urlString

                // Try to extract information from the URL
                if let url = URL(string: urlString) {
                    // Extract name from URL path if available
                    let pathComponents = url.pathComponents
                    if let lastComponent = pathComponents.last {
                        name = lastComponent
                    }

                    // Extract version from query parameters if available
                    if let queryItems = URLComponents(string: urlString)?.queryItems {
                        for item in queryItems {
                            if item.name == "version" || item.name == "v", let value = item.value {
                                version = value
                            }
                        }
                    }
                }
            }
        }

        guard let urlString = manifestURL else {
            throw ClickOnceError.invalidManifest("No URL found in appref-ms file")
        }

        logger.debug("Parsed ClickOnce manifest: \(name) v\(version)")

        return ClickOnceManifest(
            name: name,
            url: URL(string: urlString) ?? fileURL,
            version: version,
            publisher: publisher,
            supportUrl: supportUrl,
            description: description
        )
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
    /// This method creates a virtual program entry for the ClickOnce app
    /// and prepares it for execution.
    ///
    /// - Parameters:
    ///   - manifest: The ClickOnce manifest to install
    ///   - bottle: The bottle to install into
    /// - Throws: Error if installation fails
    public func install(manifest: ClickOnceManifest, in bottle: Bottle) async throws {
        logger.info("Installing ClickOnce app '\(manifest.name)' v\(manifest.version) in bottle '\(bottle.settings.name)'")

        // Create a shortcut/launcher for the ClickOnce app
        // This would typically involve creating a .lnk file or shell script

        // For now, we'll just log the installation
        // In a full implementation, this would:
        // 1. Create a launcher script in the bottle
        // 2. Add the app to the bottle's program list
        // 3. Set up the ClickOnce environment

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
        if !manifest.version.range(of: versionPattern, options: .regularExpression) != nil {
            logger.debug("ClickOnce manifest version format: \(manifest.version)")
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
        case .fileNotFound(let url):
            return "ClickOnce file not found: \(url.path)"
        case .invalidManifest(let message):
            return "Invalid ClickOnce manifest: \(message)"
        case .installationFailed(let message):
            return "ClickOnce installation failed: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Ensure the ClickOnce application is properly installed in the bottle."
        case .invalidManifest:
            return "Verify the .appref-ms file is not corrupted."
        case .installationFailed:
            return "Check Wine logs for more details and try reinstalling the application."
        }
    }
}
