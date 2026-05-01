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

        // Processor architecture (host hardware, independent of running slice)
        if HostArchitecture.isAppleSilicon {
            info += "Architecture: Apple Silicon (arm64)\n"
            if Rosetta2.isRosettaInstalled {
                info += "Rosetta 2: ✅ Installed\n"
            } else {
                info += "Rosetta 2: ❌ Not Installed\n"
            }
        } else {
            info += "Architecture: Intel (x86_64)\n"
        }

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
