//
//  Program+Extensions.swift
//  Whisky
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

// MARK: - Crash Diagnosis Notification

public extension Notification.Name {
    /// Posted when a crash diagnosis is available after a Wine process exits abnormally.
    ///
    /// UserInfo keys:
    /// - `"diagnosis"`: ``CrashDiagnosis``
    /// - `"programPath"`: `String` (program URL path)
    /// - `"logFileURL"`: `URL`
    static let crashDiagnosisAvailable = Notification.Name("com.isaacmarovitz.Whisky.crashDiagnosisAvailable")
}

// MARK: - Crash Signature Detection

private let crashSignatures: Set<String> = [
    "Unhandled exception",
    "page fault",
    "device lost",
    "DEVICE_REMOVED",
    "DEVICE_HUNG",
    "Fatal error"
]

public extension Program {
    func run() {
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            self.runInWine()
        }
    }

    /// Checks the clipboard before launching a Wine program, applying the bottle's policy.
    ///
    /// For `.needsUserDecision` results, presents a blocking alert asking the user
    /// to clear or keep the clipboard. For `.autoCleared` results, the clipboard has
    /// already been cleared by ``ClipboardManager``.
    ///
    /// - Returns: The clipboard check result after any user interaction.
    @MainActor
    func performClipboardCheck() -> ClipboardCheckResult {
        let policy = bottle.settings.clipboardPolicy
        let threshold = bottle.settings.clipboardThreshold
        let launcher = bottle.settings.detectedLauncher

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

    /// Launches the program respecting user's modifier key preference and returns the result.
    /// - Parameter useTerminal: Whether to launch in Terminal mode (e.g., Shift was held).
    ///   **Important:** Capture `NSEvent.modifierFlags.contains(.shift)` synchronously at the call site,
    ///   before entering any async context, to avoid race conditions with key state.
    /// - Returns: LaunchResult indicating success, terminal launch, or failure
    @MainActor
    func launchWithUserMode(useTerminal: Bool) async -> LaunchResult {
        // Check for terminal mode (typically shift-click)
        if useTerminal {
            self.runInTerminal()
            return .launchedInTerminal(programName: self.name)
        }

        // Normal Wine launch with program-specific settings
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()

        do {
            let result = try await Wine.runProgram(
                at: self.url, args: arguments, bottle: self.bottle, environment: environment,
                programOverrides: settings.overrides, programSettings: settings
            )

            // Track the log file URL for diagnostics
            settings.lastLogFileURL = result.logFileURL

            // Trigger classification if non-zero exit or crash signatures detected in log
            if result.exitCode != 0 || logContainsCrashSignatures(result.logFileURL) {
                triggerCrashClassification(
                    logFileURL: result.logFileURL,
                    exitCode: result.exitCode
                )
            }

            return .launchedSuccessfully(programName: self.name)
        } catch {
            return .launchFailed(programName: self.name, errorDescription: error.localizedDescription)
        }
    }

    /// Checks whether the log file contains crash signatures that warrant classification.
    ///
    /// Reads the tail of the log file (bounded to 64 KiB) and searches for known crash
    /// signatures. This is a lightweight heuristic before running the full classifier.
    private func logContainsCrashSignatures(_ logFileURL: URL) -> Bool {
        let maxBytes = 64 * 1_024

        guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return false }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd() else { return false }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)

        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else { return false }

        return crashSignatures.contains(where: { text.contains($0) })
    }

    /// Triggers background crash classification and posts a notification with the result.
    ///
    /// Classification runs on a background task (`.utility` priority) to avoid
    /// blocking the main thread. On completion, persists a ``DiagnosisHistoryEntry``
    /// and posts ``Notification.Name.crashDiagnosisAvailable``.
    private func triggerCrashClassification(logFileURL: URL, exitCode: Int32) {
        let programPath = self.url.path(percentEncoded: false)
        let programName = self.name
        let bottleName = self.bottle.settings.name
        let bottleURL = self.bottle.url
        let activePreset = self.settings.activeWineDebugPreset

        Task.detached(priority: .utility) {
            guard let diagnosis = await Wine.classifyLastRun(
                logFileURL: logFileURL,
                exitCode: exitCode
            ), !diagnosis.isEmpty
            else {
                return
            }

            // Build and persist a DiagnosisHistoryEntry
            let entry = DiagnosisHistoryEntry(
                timestamp: Date(),
                logFileRef: logFileURL.lastPathComponent,
                primaryCategory: diagnosis.primaryCategory ?? .otherUnknown,
                confidenceTier: diagnosis.primaryConfidence ?? .low,
                topSignatures: Array(diagnosis.matches.prefix(3).map(\.pattern.id)),
                remediationCardIds: diagnosis.applicableRemediationIds,
                wineDebugPreset: activePreset,
                bottleIdentifier: bottleName,
                programPath: programPath
            )

            let historyURL = bottleURL
                .appending(path: "Program Settings")
                .appending(path: programName)
                .appendingPathExtension("diagnosis-history.plist")
            var history = DiagnosisHistory.load(from: historyURL)
            history.append(entry)
            try? history.save(to: historyURL)

            // Update lastDiagnosisDate on the main actor
            await MainActor.run {
                // Post notification for the UI to react
                NotificationCenter.default.post(
                    name: .crashDiagnosisAvailable,
                    object: nil,
                    userInfo: [
                        "diagnosis": diagnosis,
                        "programPath": programPath,
                        "logFileURL": logFileURL
                    ]
                )
            }
        }
    }

    /// Generates the terminal command to run this program via Wine.
    /// - Parameter args: Optional arguments string to use instead of saved settings.
    ///   If nil, uses `settings.arguments` from the program's saved configuration.
    /// - Returns: The full Wine command string ready for terminal execution.
    func generateTerminalCommand(args: String? = nil) -> String {
        Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: args ?? settings.arguments, environment: generateEnvironment()
        )
    }

    /// Generates the terminal command to run this program via Wine with array-based arguments.
    /// - Parameter args: Array of arguments where each element is a separate argument.
    ///   Each argument is individually escaped to preserve argument boundaries.
    /// - Returns: The full Wine command string ready for terminal execution.
    func generateTerminalCommand(args: [String]) -> String {
        // Escape each argument individually to preserve argument boundaries
        // e.g., ["--name", "Player Name"] -> "--name Player\ Name" (two separate args)
        let escapedArgs = args.map(\.esc).joined(separator: " ")
        return Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: escapedArgs, environment: generateEnvironment(), preEscaped: true
        )
    }

    func runInTerminal() {
        // Write command to a temp script file to avoid AppleScript string length limits
        // and complex escaping issues with very long Wine commands
        let command = generateTerminalCommand()
        let scriptContent = "#!/bin/bash\n\(command)\n"

        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("whisky-run-\(UUID().uuidString).sh")

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            Logger.wineKit.error("Failed to write terminal script: \(error)")
            return
        }

        // Register temp script for tracking and cleanup
        TempFileTracker.shared.register(file: scriptURL)

        // Use the user's preferred terminal application
        let terminal = TerminalApp.preferred
        let appleScript = terminal.generateAppleScript(for: scriptURL.path)

        Task {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: appleScript) else { return }
            script.executeAndReturnError(&error)

            if let error {
                Logger.wineKit.error("Failed to run terminal script \(error)")
                guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                self.showRunError(message: String(describing: description))
            }

            // Clean up temp script after a delay to ensure the terminal has read it
            try? await Task.sleep(for: .seconds(5))
            await TempFileTracker.shared.cleanupWithRetry(file: scriptURL)
        }
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
            + " \(self.url.lastPathComponent): "
            + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }

    /// Shows a blocking alert when the clipboard contains large content that needs user decision.
    ///
    /// - Parameters:
    ///   - contentType: The type of clipboard content ("text", "image", or "other")
    ///   - sizeBytes: Size of the content in bytes
    ///   - textPreview: Optional preview of text content (first 50 characters)
    /// - Returns: `.autoCleared` if user chose to clear, `.safe` if user chose to keep
    @MainActor private func showClipboardAlert(
        contentType: String,
        sizeBytes: Int,
        textPreview: String?
    ) -> ClipboardCheckResult {
        let alert = NSAlert()
        alert.messageText = String(localized: "clipboard.large.title")

        let sizeKB = String(format: "%.1f", Double(sizeBytes) / 1_024.0)
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

extension Program {
    func runInWine() {
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()

        Task {
            do {
                let result = try await Wine.runProgram(
                    at: self.url, args: arguments, bottle: self.bottle, environment: environment,
                    programOverrides: settings.overrides, programSettings: settings
                )

                // Track the log file URL
                settings.lastLogFileURL = result.logFileURL

                // Trigger classification on non-zero exit or crash signatures
                if result.exitCode != 0 || logContainsCrashSignatures(result.logFileURL) {
                    triggerCrashClassification(
                        logFileURL: result.logFileURL,
                        exitCode: result.exitCode
                    )
                }
            } catch {
                self.showRunError(message: error.localizedDescription)
            }
        }
    }
}
