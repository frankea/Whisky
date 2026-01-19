//
//  TerminalApp.swift
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

/// Supported terminal applications for running Wine commands.
///
/// This enum provides AppleScript generation for launching shell scripts in different
/// terminal applications. Use ``generateAppleScript(for:)`` to execute a script file.
///
/// ## Terminal Support Notes
///
/// - **Terminal.app**: Full AppleScript support via `do script`
/// - **iTerm2**: Full AppleScript support via `write text`
/// - **Warp**: Limited AppleScript support; uses `open -a Warp` to launch script files.
///   Warp executes `.sh` files when opened if they have executable permissions.
public enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal
    case iterm
    case warp

    public var id: String { rawValue }

    /// The display name for the terminal application.
    public var displayName: String {
        switch self {
        case .terminal:
            "Terminal"
        case .iterm:
            "iTerm2"
        case .warp:
            "Warp"
        }
    }

    /// The bundle identifier for the terminal application.
    public var bundleIdentifier: String {
        switch self {
        case .terminal:
            "com.apple.Terminal"
        case .iterm:
            "com.googlecode.iterm2"
        case .warp:
            "dev.warp.Warp-Stable"
        }
    }

    /// Whether this terminal application is installed on the system.
    public var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Returns the list of installed terminal applications.
    public static var installedTerminals: [TerminalApp] {
        allCases.filter(\.isInstalled)
    }

    /// The user's preferred terminal application.
    /// Falls back to Terminal.app if the preferred app is not installed.
    public static var preferred: TerminalApp {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "preferredTerminal") ?? "terminal"
            let preferred = TerminalApp(rawValue: rawValue) ?? .terminal
            // Fall back to Terminal if preferred is not installed
            return preferred.isInstalled ? preferred : .terminal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "preferredTerminal")
        }
    }

    /// Generates an AppleScript to run the given script file in this terminal.
    /// - Parameter scriptPath: The path to the shell script to execute.
    /// - Returns: The AppleScript source code.
    public func generateAppleScript(for scriptPath: String) -> String {
        let escapedPath = scriptPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch self {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "source \\"\(escapedPath)\\""
            end tell
            """

        case .iterm:
            return """
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window
                    write text "source \\"\(escapedPath)\\""
                end tell
            end tell
            """

        case .warp:
            // Warp doesn't support AppleScript's `do script` or `write text` commands.
            // Instead, we use `open -a Warp` with the script file, which Warp will execute
            // if the file has executable permissions (.sh extension and chmod +x).
            return """
            tell application "Warp"
                activate
            end tell
            do shell script "open -a Warp \\"\(escapedPath)\\""
            """
        }
    }

    /// Generates an AppleScript to run a command directly in a terminal window.
    ///
    /// - Note: This method is deprecated. Prefer writing commands to a temporary script file
    ///   and using ``generateAppleScript(for:)`` instead, which provides consistent behavior
    ///   across all terminal applications and proper temp file cleanup.
    ///
    /// For Warp, this method creates a temporary script file since Warp doesn't support
    /// AppleScript's `do script` command. However, the temp file is never cleaned up when
    /// using this method directly.
    ///
    /// - Parameter command: The shell command to execute.
    /// - Returns: The AppleScript source code, or `nil` if script file creation failed (Warp only).
    @available(*, deprecated, message: "Use generateAppleScript(for:) with a temp script file instead")
    public func generateDirectCommandScript(command: String) -> String? {
        switch self {
        case .terminal:
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\\\\\")
                .replacingOccurrences(of: "\"", with: "\\\\\\\"")
            return """
            tell application "Terminal"
            activate
            do script "\(escaped)"
            end tell
            """

        case .iterm:
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\\\\\")
                .replacingOccurrences(of: "\"", with: "\\\\\\\"")
            return """
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window
                    write text "\(escaped)"
                end tell
            end tell
            """

        case .warp:
            // Warp requires a script file since it doesn't support do script
            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("whisky-env-\(UUID().uuidString).sh")
            let unescaped = command.replacingOccurrences(of: "\\\"", with: "\"")
            let content = "#!/bin/bash\n\(unescaped)\n"

            do {
                try content.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            } catch {
                return nil
            }

            let escapedPath = scriptURL.path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return """
            tell application "Warp"
                activate
            end tell
            do shell script "open -a Warp \\"\(escapedPath)\\""
            """
        }
    }
}
