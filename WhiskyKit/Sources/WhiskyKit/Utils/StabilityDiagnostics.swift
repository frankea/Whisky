//
//  StabilityDiagnostics.swift
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

/// Diagnostic utilities for troubleshooting critical stability issues (frankea/Whisky#40).
///
/// Goals:
/// - Keep output bounded (safe to paste into GitHub issues).
/// - Avoid leaking secrets or sensitive values (environment keys only).
/// - Provide enough system/bottle context to reproduce and triage.
public enum StabilityDiagnostics {
    public struct Configuration: Sendable {
        public var bundle: Bundle
        public var logsFolder: URL
        public var now: @Sendable () -> Date

        public init(
            bundle: Bundle = .main,
            logsFolder: URL = Wine.logsFolder,
            now: @escaping @Sendable () -> Date = Date.init
        ) {
            self.bundle = bundle
            self.logsFolder = logsFolder
            self.now = now
        }
    }

    @MainActor
    public static func generateDiagnosticReport(
        for bottle: Bottle,
        config: Configuration = .init()
    ) async -> String {
        var report = """
        ═══════════════════════════════════════════════════════
        Whisky Stability Diagnostics Report
        Generated: \(config.now().formatted())
        ═══════════════════════════════════════════════════════

        """

        report += await generateSystemInfo(config: config)
        report += generateBottleSummary(for: bottle)
        report += generateEnvironmentKeySnapshot(for: bottle)
        report += await generateLogSummary(config: config)

        report += """

        ═══════════════════════════════════════════════════════
        End of Diagnostic Report
        ═══════════════════════════════════════════════════════
        """

        return report
    }

    @MainActor
    private static func generateSystemInfo(config: Configuration) async -> String {
        var info = """

        [SYSTEM INFORMATION]

        """

        let version = MacOSVersion.current
        info += "macOS Version: \(version.description)\n"

        #if arch(arm64)
        info += "Architecture: Apple Silicon (arm64)\n"
        info += "Rosetta 2: \(Rosetta2.isRosettaInstalled ? "✅ Installed" : "❌ Not Installed")\n"
        #else
        info += "Architecture: Intel (x86_64)\n"
        #endif

        let appVersion = config.bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let buildNumber = config.bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if !appVersion.isEmpty {
            info += "Whisky Version: \(appVersion)\(buildNumber.isEmpty ? "" : " (\(buildNumber))")\n"
        }

        if let whiskyWineVersion = WhiskyWineInstaller.whiskyWineVersion() {
            let whiskyWineVersionString =
                "\(whiskyWineVersion.major).\(whiskyWineVersion.minor).\(whiskyWineVersion.patch)"
            info += "WhiskyWine Version: \(whiskyWineVersionString)\n"
        } else {
            info += "WhiskyWine Version: Not installed / unknown\n"
        }

        info += "\n"
        return info
    }

    @MainActor
    private static func generateBottleSummary(for bottle: Bottle) -> String {
        var summary = """
        [BOTTLE SUMMARY]

        """

        summary += "Bottle Name: \(bottle.settings.name)\n"
        summary += "Windows Version: \(bottle.settings.windowsVersion)\n"
        summary += "Bottle Wine Version: \(bottle.settings.wineVersion)\n\n"

        summary += "--- Graphics/Metal ---\n"
        summary += "DXVK: \(bottle.settings.dxvk ? "✅ Enabled" : "❌ Disabled")\n"
        summary += "DXVK Async: \(bottle.settings.dxvkAsync ? "✅ Enabled" : "❌ Disabled")\n"
        summary += "Force D3D11: \(bottle.settings.forceD3D11 ? "✅ Yes" : "❌ No")\n"
        summary += "DXR Enabled: \(bottle.settings.dxrEnabled ? "✅ Yes" : "❌ No")\n"
        summary += "Metal HUD: \(bottle.settings.metalHud ? "✅ Yes" : "❌ No")\n"
        summary += "Metal Validation: \(bottle.settings.metalValidation ? "✅ Yes" : "❌ No")\n"
        summary += "Sequoia Compat Mode: \(bottle.settings.sequoiaCompatMode ? "✅ Yes" : "❌ No")\n\n"

        summary += "--- Sync/Performance ---\n"
        summary += "Enhanced Sync: \(bottle.settings.enhancedSync)\n"
        summary += "Performance Preset: \(bottle.settings.performancePreset)\n"
        summary += "Shader Cache: \(bottle.settings.shaderCacheEnabled ? "✅ Enabled" : "❌ Disabled")\n"
        summary += "AVX Enabled: \(bottle.settings.avxEnabled ? "✅ Yes" : "❌ No")\n\n"

        summary += "--- Launcher Compatibility ---\n"
        let launcherCompatibilityStatus = bottle.settings.launcherCompatibilityMode ? "✅ Enabled" : "❌ Disabled"
        summary += "Launcher Compatibility Mode: \(launcherCompatibilityStatus)\n"
        if let launcher = bottle.settings.detectedLauncher {
            summary += "Detected Launcher: \(launcher.rawValue)\n"
        } else {
            summary += "Detected Launcher: None\n"
        }
        summary += "\n"

        return summary
    }

    @MainActor
    private static func generateEnvironmentKeySnapshot(for bottle: Bottle) -> String {
        var snapshot = """
        [ENVIRONMENT (KEYS ONLY)]

        """

        let envKeys = Wine.constructWineEnvironment(for: bottle, environment: [:])
            .keys
            .sorted()

        // Keys only: avoid persisting sensitive values (paths, tokens, etc.).
        for key in envKeys {
            snapshot += "\(key)\n"
        }

        snapshot += "\n"
        return snapshot
    }

    // swiftlint:disable:next function_body_length
    private static func generateLogSummary(config: Configuration) async -> String {
        await Task.detached(priority: .utility) {
            var logs = """
            [LOGS]

            """

            let folder = config.logsFolder
            let folderPath = folder.path(percentEncoded: false)
            logs += "Logs Folder: \(folderPath)\n"

            guard FileManager.default.fileExists(atPath: folderPath) else {
                logs += "Logs Folder Status: Not found\n\n"
                return logs
            }

            do {
                let keys: [URLResourceKey] = [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey
                ]
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                )

                struct LogFile {
                    let url: URL
                    let size: Int
                    let date: Date
                }

                var files: [LogFile] = []
                files.reserveCapacity(urls.count)

                for url in urls where url.pathExtension.lowercased() == "log" {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isRegularFile == true else { continue }
                    let size = values.fileSize ?? 0
                    let date = values.contentModificationDate ?? values.creationDate ?? .distantPast
                    files.append(LogFile(url: url, size: size, date: date))
                }

                if files.isEmpty {
                    logs += "Log Files: None found\n\n"
                    return logs
                }

                files.sort { $0.date > $1.date } // newest first

                let formatter = ByteCountFormatter()
                formatter.countStyle = .file

                logs += "Most Recent Logs:\n"
                for file in files.prefix(5) {
                    let sizeString = formatter.string(fromByteCount: Int64(file.size))
                    logs += "- \(file.url.lastPathComponent) (\(sizeString), \(file.date.formatted()))\n"
                }

                if let newest = files.first {
                    logs += "\n--- Tail of newest log (bounded) ---\n"
                    logs += tailOfLogFile(newest.url) + "\n"
                    logs += "--- End tail ---\n"
                }

                logs += "\n"
                return logs
            } catch {
                logs += "Failed to enumerate logs: \(error.localizedDescription)\n\n"
                return logs
            }
        }.value
    }

    static func tailOfLogFile(_ url: URL) -> String {
        // Keep this small and predictable: max 64 KiB, last 200 lines.
        let maxBytesToRead = 64 * 1_024
        let maxLines = 200

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let end = try handle.seekToEnd()
            let start = end > UInt64(maxBytesToRead) ? end - UInt64(maxBytesToRead) : 0
            try handle.seek(toOffset: start)

            let data = try handle.readToEnd() ?? Data()
            guard var text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return "(Log tail unavailable: not UTF-8 or empty)"
            }

            // If we started from the middle, drop the first partial line.
            if start != 0, let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }

            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count <= maxLines {
                return lines.joined(separator: "\n")
            }
            return lines.suffix(maxLines).joined(separator: "\n")
        } catch {
            return "(Failed to read log tail: \(error.localizedDescription))"
        }
    }
}
