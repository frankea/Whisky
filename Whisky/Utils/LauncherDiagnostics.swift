//
//  LauncherDiagnostics.swift
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

// swiftlint:disable file_length

import Foundation
import WhiskyKit

/// Diagnostic utilities for troubleshooting launcher compatibility issues.
///
/// ## Overview
///
/// This system provides comprehensive diagnostics for debugging launcher problems
/// related to frankea/Whisky#41. It generates detailed reports of bottle configuration,
/// environment variables, system state, and validates settings against known
/// working configurations.
///
/// ## Use Cases
///
/// - Generate bug reports for GitHub issues
/// - Troubleshoot launcher crashes and failures
/// - Validate bottle configuration before launching games
/// - Compare settings against recommended configurations
///
/// ## Example
///
/// ```swift
/// @MainActor
/// let report = await LauncherDiagnostics.generateDiagnosticReport(for: bottle)
/// print(report)
/// // Export to file for support requests
/// ```
enum LauncherDiagnostics {
    /// Generates a comprehensive diagnostic report for a bottle.
    ///
    /// This report includes system information, bottle configuration, environment
    /// variables, and validation results. The output is formatted for easy sharing
    /// in GitHub issues or support requests.
    ///
    /// - Parameter bottle: The bottle to generate diagnostics for
    /// - Returns: Multi-line diagnostic report string
    @MainActor
    static func generateDiagnosticReport(for bottle: Bottle) async -> String {
        var report = """
        ═══════════════════════════════════════════════════════
        Whisky Launcher Diagnostics Report
        Generated: \(Date().formatted())
        ═══════════════════════════════════════════════════════

        """

        // System Information
        report += await generateSystemInfo()

        // Bottle Configuration
        report += generateBottleConfig(for: bottle)

        // Environment Variables
        report += generateEnvironmentSnapshot(for: bottle)

        // Validation Results
        report += generateValidationResults(for: bottle)

        // Recommendations
        report += generateRecommendations(for: bottle)

        report += """

        ═══════════════════════════════════════════════════════
        End of Diagnostic Report
        ═══════════════════════════════════════════════════════
        """

        return report
    }

    /// Generates system information section.
    @MainActor
    private static func generateSystemInfo() async -> String {
        var info = """

        [SYSTEM INFORMATION]

        """

        let version = MacOSVersion.current
        info += "macOS Version: \(version.description)\n"

        // Wine version
        if let wineVer = try? await Wine.wineVersion() {
            info += "Wine Version: \(wineVer)\n"
        } else {
            info += "Wine Version: Unable to detect\n"
        }

        // Processor architecture
        #if arch(arm64)
        info += "Architecture: Apple Silicon (arm64)\n"
        #else
        info += "Architecture: Intel (x86_64)\n"
        #endif

        // Rosetta 2 status (for Apple Silicon)
        #if arch(arm64)
        if Rosetta2.isRosettaInstalled {
            info += "Rosetta 2: ✅ Installed\n"
        } else {
            info += "Rosetta 2: ❌ Not Installed\n"
        }
        #endif

        info += "\n"
        return info
    }

    /// Generates bottle configuration section.
    @MainActor
    private static func generateBottleConfig(for bottle: Bottle) -> String {
        var config = """
        [BOTTLE CONFIGURATION]

        """

        config += "Bottle Name: \(bottle.settings.name)\n"
        config += "Bottle URL: \(bottle.url.path)\n"
        config += "Windows Version: \(bottle.settings.windowsVersion)\n"
        config += "Wine Version: \(bottle.settings.wineVersion)\n\n"

        // Launcher Compatibility Settings
        config += "--- Launcher Compatibility ---\n"
        config += "Compatibility Mode: \(bottle.settings.launcherCompatibilityMode ? "✅ Enabled" : "❌ Disabled")\n"
        config += "Detection Mode: \(bottle.settings.launcherMode.rawValue)\n"
        if let launcher = bottle.settings.detectedLauncher {
            config += "Detected Launcher: \(launcher.rawValue)\n"
        } else {
            config += "Detected Launcher: None\n"
        }
        config += "Launcher Locale: \(bottle.settings.launcherLocale.pretty())\n"
        config += "GPU Spoofing: \(bottle.settings.gpuSpoofing ? "✅ Enabled" : "❌ Disabled")\n"
        if bottle.settings.gpuSpoofing {
            config += "GPU Vendor: \(bottle.settings.gpuVendor.rawValue)\n"
        }
        config += "Network Timeout: \(bottle.settings.networkTimeout)ms\n"
        config += "Auto-Enable DXVK: \(bottle.settings.autoEnableDXVK ? "✅ Yes" : "❌ No")\n\n"

        // Graphics Settings
        config += "--- Graphics Configuration ---\n"
        config += "DXVK: \(bottle.settings.dxvk ? "✅ Enabled" : "❌ Disabled")\n"
        if bottle.settings.dxvk {
            config += "DXVK Async: \(bottle.settings.dxvkAsync ? "✅ Enabled" : "❌ Disabled")\n"
            config += "DXVK HUD: \(bottle.settings.dxvkHud)\n"
        }
        config += "Metal HUD: \(bottle.settings.metalHud ? "✅ Enabled" : "❌ Disabled")\n"
        config += "DXR Support: \(bottle.settings.dxrEnabled ? "✅ Enabled" : "❌ Disabled")\n"
        config += "Metal Validation: \(bottle.settings.metalValidation ? "✅ Enabled" : "❌ Disabled")\n"
        config += "Sequoia Compat Mode: \(bottle.settings.sequoiaCompatMode ? "✅ Enabled" : "❌ Disabled")\n\n"

        // Performance Settings
        config += "--- Performance Configuration ---\n"
        config += "Performance Preset: \(bottle.settings.performancePreset)\n"
        config += "Enhanced Sync: \(bottle.settings.enhancedSync)\n"
        config += "Shader Cache: \(bottle.settings.shaderCacheEnabled ? "✅ Enabled" : "❌ Disabled")\n"
        config += "Force D3D11: \(bottle.settings.forceD3D11 ? "✅ Yes" : "❌ No")\n"
        config += "AVX Enabled: \(bottle.settings.avxEnabled ? "✅ Yes" : "❌ No")\n\n"

        return config
    }

    /// Generates environment variables snapshot.
    @MainActor
    private static func generateEnvironmentSnapshot(for bottle: Bottle) -> String {
        var snapshot = """
        [ENVIRONMENT VARIABLES]

        """

        var env: [String: String] = [:]
        for (key, value) in Wine.constructWineEnvironment(for: bottle, environment: [:]) {
            env[key] = value
        }

        // Sort for readability
        let sortedEnv = env.sorted { $0.key < $1.key }

        for (key, value) in sortedEnv {
            // Truncate very long values for readability
            let displayValue = value.count > 100 ? "\(value.prefix(97))..." : value
            snapshot += "\(key) = \(displayValue)\n"
        }

        snapshot += "\n"
        return snapshot
    }

    /// Generates validation results section.
    @MainActor
    private static func generateValidationResults(for bottle: Bottle) -> String {
        var validation = """
        [VALIDATION RESULTS]

        """

        if let launcher = bottle.settings.detectedLauncher {
            let warnings = LauncherDetection.validateBottleForLauncher(bottle, launcher: launcher)

            if warnings.isEmpty {
                validation += "✅ Configuration is optimal for \(launcher.rawValue)\n\n"
            } else {
                validation += "⚠️  Configuration warnings for \(launcher.rawValue):\n\n"
                for warning in warnings {
                    validation += "  \(warning)\n"
                }
                validation += "\n"
            }
        } else {
            validation += "ℹ️  No launcher detected. Configuration not validated.\n\n"
        }

        // Check GPU spoofing environment
        if bottle.settings.gpuSpoofing {
            var testEnv: [String: String] = [:]
            bottle.settings.environmentVariables(wineEnv: &testEnv)

            if GPUDetection.validateSpoofingEnvironment(testEnv) {
                validation += "✅ GPU spoofing environment is properly configured\n"
            } else {
                validation += "❌ GPU spoofing environment is incomplete\n"
            }
        }

        validation += "\n"
        return validation
    }

    /// Generates recommendations section.
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private static func generateRecommendations(for bottle: Bottle) -> String {
        var recommendations = """
        [RECOMMENDATIONS]

        """

        var hasRecommendations = false

        // Launcher compatibility mode check
        if !bottle.settings.launcherCompatibilityMode {
            recommendations += "💡 Enable Launcher Compatibility Mode for automatic fixes\n"
            hasRecommendations = true
        }

        // macOS version specific
        let version = MacOSVersion.current
        if version >= .sequoia15_4 {
            if !bottle.settings.sequoiaCompatMode {
                recommendations += "💡 Enable Sequoia Compatibility Mode for macOS 15.4+ stability\n"
                hasRecommendations = true
            }
        }

        // Launcher-specific recommendations
        if let launcher = bottle.settings.detectedLauncher {
            switch launcher {
            case .steam:
                if !bottle.settings.dxvk {
                    recommendations += "💡 Enable DXVK for better Steam performance\n"
                    hasRecommendations = true
                }
                if bottle.settings.networkTimeout < 90_000 {
                    recommendations += "💡 Increase network timeout to 90000ms for Steam downloads\n"
                    hasRecommendations = true
                }

            case .rockstar:
                if !bottle.settings.dxvk {
                    recommendations += "❗️ CRITICAL: Enable DXVK (required for Rockstar Launcher)\n"
                    hasRecommendations = true
                }

            case .eaApp:
                if !bottle.settings.gpuSpoofing {
                    recommendations += "❗️ CRITICAL: Enable GPU spoofing (required for EA App)\n"
                    hasRecommendations = true
                }

            default:
                break
            }
        }

        if !hasRecommendations {
            recommendations += "✅ No additional recommendations at this time\n"
        }

        recommendations += "\n"
        return recommendations
    }

    /// Exports diagnostic report to a file.
    ///
    /// - Parameters:
    ///   - report: The diagnostic report string
    ///   - filename: Optional filename (default: "whisky-diagnostics-<timestamp>.txt")
    /// - Returns: URL to the exported file
    /// - Throws: Error if file cannot be written
    @discardableResult
    static func exportReport(_ report: String, filename: String? = nil) throws -> URL {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let finalFilename = filename ?? "whisky-diagnostics-\(timestamp).txt"

        let fileURL = documentsURL.appendingPathComponent(finalFilename)
        try report.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}

/// Diagnostic utilities for troubleshooting critical stability issues (issue #40).
///
/// Goals:
/// - Keep output bounded (safe to paste into GitHub issues).
/// - Avoid leaking secrets or sensitive values (environment keys only).
/// - Provide enough system/bottle context to reproduce and triage.
enum StabilityDiagnostics {
    @MainActor
    static func generateDiagnosticReport(for bottle: Bottle) async -> String {
        var report = """
        ═══════════════════════════════════════════════════════
        Whisky Stability Diagnostics Report
        Generated: \(Date().formatted())
        ═══════════════════════════════════════════════════════

        """

        report += await generateSystemInfo()
        report += generateBottleSummary(for: bottle)
        report += generateEnvironmentKeySnapshot(for: bottle)
        report += await generateLogSummary()

        report += """

        ═══════════════════════════════════════════════════════
        End of Diagnostic Report
        ═══════════════════════════════════════════════════════
        """

        return report
    }

    @MainActor
    private static func generateSystemInfo() async -> String {
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

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
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
    private static func generateLogSummary() async -> String {
        await Task.detached(priority: .utility) {
            var logs = """
            [LOGS]

            """

            let folder = Wine.logsFolder
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

    private static func tailOfLogFile(_ url: URL) -> String {
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
