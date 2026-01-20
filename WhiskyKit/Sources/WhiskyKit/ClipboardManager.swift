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

/// Manager for clipboard operations to prevent Wine-related freezes.
///
/// This singleton provides methods to detect, clear, and sanitize clipboard
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
/// // Sanitize for multiplayer launcher
/// ClipboardManager.shared.sanitizeForMultiplayer(launcher: .steam)
/// ```
public final class ClipboardManager: @unchecked Sendable {
    static let shared = ClipboardManager()

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

    /// Sanitizes the clipboard for multiplayer games.
    ///
    /// This method checks if the clipboard contains large content and warns the user.
    /// For known multiplayer launchers, it automatically clears the clipboard.
    ///
    /// - Parameter autoClearForMultiplayer: If true, automatically clears clipboard for multiplayer launchers
    @MainActor
    public func sanitizeForMultiplayer(autoClearForMultiplayer: Bool = false) {
        let content = getContent()
        let size = getSize()

        // Check if content is large
        if size > Self.largeContentThreshold {
            logger.warning("Large clipboard content detected (\(size) bytes)")

            // Auto-clear for known multiplayer launchers
            if autoClearForMultiplayer {
                clear()
                logger.info("Auto-cleared clipboard for multiplayer launcher")
                return
            }

            // Show alert to user for manual decision
            showLargeClipboardAlert(size: size, content: content)
        }
    }

    /// Shows an alert about large clipboard content.
    ///
    /// This is called when clipboard content exceeds the threshold and the launcher
    /// is not a known multiplayer type.
    ///
    /// - Parameters:
    ///   - size: Size of clipboard content in bytes
    ///   - content: The clipboard content type
    @MainActor
    private func showLargeClipboardAlert(size: Int, content: ClipboardContent) {
        let alert = NSAlert()
        alert.messageText = String(localized: "clipboard.large.title")
        alert.alertStyle = .warning

        let sizeKB = Double(size) / 1_024.0
        let message: String

        switch content {
        case let .text(string):
            let preview = String(string.prefix(50))
            message = String(localized: "clipboard.large.message.text")
                .replacingOccurrences(of: "{size}", with: String(format: "%.1f", sizeKB))
                .replacingOccurrences(of: "{preview}", with: preview)
        case .image:
            message = String(localized: "clipboard.large.message.image")
                .replacingOccurrences(of: "{size}", with: String(format: "%.1f", sizeKB))
        case .other:
            message = String(localized: "clipboard.large.message.other")
                .replacingOccurrences(of: "{size}", with: String(format: "%.1f", sizeKB))
        case .empty:
            message = String(localized: "clipboard.large.message.empty")
        }

        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "clipboard.clear"))
        alert.addButton(withTitle: String(localized: "clipboard.keep"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            clear()
        }
    }
}
