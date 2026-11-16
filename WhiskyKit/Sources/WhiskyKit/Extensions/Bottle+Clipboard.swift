//
//  Bottle+Clipboard.swift
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

public extension Bottle {
    /// Checks the clipboard before launching a Wine program in this bottle, applying its policy.
    ///
    /// For `.needsUserDecision` results, presents a blocking alert asking the user
    /// to clear or keep the clipboard. For `.autoCleared` results, the clipboard has
    /// already been cleared by ``ClipboardManager``.
    ///
    /// - Returns: The clipboard check result after any user interaction.
    @MainActor
    func performClipboardCheck() -> ClipboardCheckResult {
        let policy = settings.clipboardPolicy
        let threshold = settings.clipboardThreshold
        let launcher = settings.detectedLauncher

        let result = ClipboardManager.shared.checkBeforeLaunch(
            launcher: launcher, policy: policy, threshold: threshold
        )

        switch result {
        case .safe, .autoCleared:
            return result
        case let .needsUserDecision(contentType, sizeBytes, textPreview):
            return showClipboardAlert(
                contentType: contentType, sizeBytes: sizeBytes, textPreview: textPreview
            )
        }
    }
}

private extension Bottle {
    /// Shows a blocking alert when the clipboard contains large content that needs user decision.
    ///
    /// - Parameters:
    ///   - contentType: The type of clipboard content ("text", "image", or "other")
    ///   - sizeBytes: Size of the content in bytes
    ///   - textPreview: Optional preview of text content (first 50 characters)
    /// - Returns: `.autoCleared` if user chose to clear, `.safe` if user chose to keep
    @MainActor func showClipboardAlert(
        contentType: String,
        sizeBytes: Int,
        textPreview: String?
    ) -> ClipboardCheckResult {
        let alert = NSAlert()
        alert.messageText = String(localized: "clipboard.large.title")

        let sizeKB = (Double(sizeBytes) / 1_024.0).formatted(.number.precision(.fractionLength(1)))
        let message: String
        switch contentType {
        case "text":
            let preview = textPreview ?? ""
            message = String(localized: "clipboard.large.message.text")
                .replacingOccurrences(of: "{size}", with: sizeKB)
                .replacingOccurrences(of: "{preview}", with: preview)
        case "image":
            message = String(localized: "clipboard.large.message.image")
                .replacingOccurrences(of: "{size}", with: sizeKB)
        default:
            message = String(localized: "clipboard.large.message.other")
                .replacingOccurrences(of: "{size}", with: sizeKB)
        }

        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "clipboard.clear"))
        alert.addButton(withTitle: String(localized: "clipboard.keep"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            ClipboardManager.shared.clear()
            return .autoCleared(contentType: contentType, sizeBytes: sizeBytes)
        }
        return .safe
    }
}
