//
//  ClipboardManager.swift
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

import AppKit
import Foundation
import os.log

/// Per-bottle clipboard handling policy.
///
/// Controls how the clipboard is checked and managed before launching Wine programs.
/// Each bottle can specify its own policy, or use the default `auto` behavior.
public enum ClipboardPolicy: String, Codable, CaseIterable, Sendable {
    /// Auto-clear for known multiplayer launchers, warn for others (default)
    case auto = "auto"
    /// Always show a warning when clipboard content is large
    case alwaysWarn = "warn"
    /// Always clear the clipboard before launching
    case alwaysClear = "clear"
    /// Never warn or clear the clipboard
    case never = "never"
}

/// Result of a clipboard check before launching a Wine program.
///
/// The app layer uses this to decide whether to show a toast, alert, or proceed silently.
public enum ClipboardCheckResult: Sendable {
    /// Content is small or empty, no action needed
    case safe
    /// Content was auto-cleared (for known multiplayer launchers or always-clear policy)
    case autoCleared(contentType: String, sizeBytes: Int)
    /// Content is large and needs user decision (show alert/sheet in app layer)
    case needsUserDecision(contentType: String, sizeBytes: Int, textPreview: String?)
}

/// Manager for clipboard operations to prevent Wine-related freezes.
///
/// This singleton provides methods to detect, clear, and check clipboard
/// content before Wine operations, particularly for multiplayer games that may
/// attempt to read clipboard synchronously.
///
/// ## Usage
///
/// ```swift
/// // Check clipboard content
/// let content = ClipboardManager.shared.getContent()
///
/// // Clear clipboard
/// ClipboardManager.shared.clear()
///
/// // Check before launching a program
/// let result = ClipboardManager.shared.checkBeforeLaunch(launcher: .steam, policy: .auto)
/// ```
public final class ClipboardManager: @unchecked Sendable {
    public static let shared = ClipboardManager()

    private let pasteboard = NSPasteboard.general
    private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ClipboardManager")

    /// Size threshold for considering clipboard content "large" (10 KB)
    public static let largeContentThreshold: Int = 10 * 1_024 // 10 KB

    /// Types of clipboard content.
    public enum ClipboardContent: @unchecked Sendable {
        case empty
        case text(String)
        case image(NSImage)
        case other

        /// Returns the size of content in bytes.
        public var sizeInBytes: Int {
            switch self {
            case .empty:
                return 0
            case let .text(string):
                return string.utf8.count
            case let .image(image):
                // Estimate image size (TIFF representation)
                guard let tiffData = image.tiffRepresentation else { return 0 }
                return tiffData.count
            case .other:
                // Can't determine size for other content types
                return 0
            }
        }
    }

    private init() {}

    // MARK: - Content Querying

    /// Returns the current clipboard content.
    ///
    /// This method checks for text, images, and other content types.
    ///
    /// - Returns: ClipboardContent enum describing the current state
    public func getContent() -> ClipboardContent {
        // Check for string content
        if let string = pasteboard.string(forType: .string) {
            return !string.isEmpty ? .text(string) : .empty
        }

        // Check for image content
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: [:])?.first as? NSImage {
            return .image(image)
        }

        // Check for other content types
        if pasteboard.types?.isEmpty == false {
            return .other
        }

        return .empty
    }

    /// Returns the size of the current clipboard content in bytes.
    ///
    /// - Returns: Size in bytes (0 if empty or unknown)
    public func getSize() -> Int {
        getContent().sizeInBytes
    }

    /// Checks if the current clipboard content is considered "large".
    ///
    /// Content larger than 10 KB is considered large and may cause issues.
    ///
    /// - Returns: true if content is larger than threshold, false otherwise
    public func isLarge() -> Bool {
        getSize() > Self.largeContentThreshold
    }

    // MARK: - Modification

    /// Clears the clipboard.
    ///
    /// This method removes all content from the general pasteboard.
    public func clear() {
        pasteboard.clearContents()
        logger.info("Clipboard cleared")
    }

    // MARK: - Pre-launch Check

    /// Checks the clipboard before launching a Wine program and returns a structured result.
    ///
    /// The caller (app layer) is responsible for presenting any UI based on the result.
    /// This method may auto-clear the clipboard depending on the policy and launcher type.
    ///
    /// - Parameters:
    ///   - launcher: The detected launcher type (optional)
    ///   - policy: The per-bottle clipboard policy
    ///   - threshold: Size threshold in bytes (defaults to ``largeContentThreshold``)
    /// - Returns: A ``ClipboardCheckResult`` indicating what action was taken or is needed
    public func checkBeforeLaunch(
        launcher: LauncherType? = nil,
        policy: ClipboardPolicy,
        threshold: Int = ClipboardManager.largeContentThreshold
    ) -> ClipboardCheckResult {
        // Never policy: skip all checks
        if policy == .never {
            return .safe
        }

        let content = getContent()
        let size = content.sizeInBytes

        // Content below threshold is always safe
        guard size > threshold else {
            return .safe
        }

        logger.warning("Large clipboard content detected (\(size) bytes)")

        let contentType = Self.contentTypeName(for: content)
        let textPreview = Self.textPreview(for: content)

        // Always-clear policy: clear and report
        if policy == .alwaysClear {
            clear()
            logger.info("Auto-cleared clipboard (always-clear policy)")
            return .autoCleared(contentType: contentType, sizeBytes: size)
        }

        // Auto policy with known multiplayer launcher: auto-clear
        if policy == .auto, launcher?.usesClipboard == true {
            clear()
            logger.info("Auto-cleared clipboard for multiplayer launcher '\(launcher?.displayName ?? "unknown")'")
            return .autoCleared(contentType: contentType, sizeBytes: size)
        }

        // Always-warn policy or auto policy without launcher match: needs user decision
        return .needsUserDecision(contentType: contentType, sizeBytes: size, textPreview: textPreview)
    }

    // MARK: - Private Helpers

    /// Returns a human-readable content type name for the clipboard content.
    private static func contentTypeName(for content: ClipboardContent) -> String {
        switch content {
        case .empty:
            "empty"
        case .text:
            "text"
        case .image:
            "image"
        case .other:
            "other"
        }
    }

    /// Returns a text preview (first 50 characters) for text content, nil otherwise.
    private static func textPreview(for content: ClipboardContent) -> String? {
        switch content {
        case let .text(string):
            String(string.prefix(50))
        default:
            nil
        }
    }
}
