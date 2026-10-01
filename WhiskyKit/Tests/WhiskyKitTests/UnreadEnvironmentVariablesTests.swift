//
//  UnreadEnvironmentVariablesTests.swift
//  WhiskyKitTests
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

@testable import WhiskyKit
import XCTest

/// Variables Whisky used to set that no shipped runtime reads.
///
/// None of these names occurs, in ASCII or UTF-16LE, in any file of the Wine
/// Libraries v2.5.0, v3.0.0, v3.1.1 or v4.6.4-beta.1 trees (Wine, DXVK, DXMT and
/// the bundled D3DMetal) or of the imported GPTK 4.0b2 D3DMetal payload, and
/// none is a Steam or CEF switch.
private let unreadVariables = [
    "D3DM_VALIDATION",
    "WINE_DISABLE_NTDLL_THREAD_REGS",
    "WINE_ENABLE_PIPE_SYNC_FOR_APP",
    "WINE_CPU_TOPOLOGY",
    "WINE_THREAD_PRIORITY_PRESERVE",
    "WINE_ENABLE_POSIX_SIGNALS",
    "WINE_SIGPIPE_IGNORE",
    "WINE_PRELOADER_DEBUG",
    "WINE_DISABLE_FAST_PATH",
    "WINE_MACH_PORT_TIMEOUT",
    "WINE_MACH_PORT_RETRY_COUNT",
    "DXVK_REQUIRED",
    "GPU_VENDOR_ID",
    "GPU_DEVICE_ID",
    "GPU_DESCRIPTION",
    "GPU_MEMORY_SIZE",
    "D3DM_SHADER_MODEL"
]

final class UnreadEnvironmentVariablesTests: XCTestCase {
    func testPlatformRegistryHoldsOnlyReadVariables() {
        let keys = Set(MacOSCompatibilityFixes.allFixes.map(\.key))
        XCTAssertEqual(
            keys,
            ["STEAM_DISABLE_CEF_SANDBOX", "CEF_DISABLE_SANDBOX", "MTL_DEBUG_LAYER", "WINEFSYNC", "STEAM_RUNTIME"]
        )
    }

    @MainActor
    func testLaunchEnvironmentOmitsUnreadVariables() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.gpuSpoofing = true

        for launcher in LauncherType.allCases {
            bottle.settings.detectedLauncher = launcher
            let env = Wine.constructWineEnvironment(for: bottle)
            for name in unreadVariables {
                XCTAssertNil(env[name], "\(name) set for \(launcher.rawValue)")
            }
            // The read platform fixes are still there.
            XCTAssertEqual(env["CEF_DISABLE_SANDBOX"], "1")
            XCTAssertEqual(env["WINEFSYNC"], "0")
        }
    }

    func testLauncherPresetsOmitUnreadVariables() {
        for launcher in LauncherType.allCases {
            let env = launcher.environmentOverrides()
            let detailKeys = launcher.fixDetails().map(\.key)
            for name in unreadVariables {
                XCTAssertNil(env[name], "\(name) in \(launcher.rawValue) preset")
                XCTAssertFalse(detailKeys.contains(name), "\(name) in \(launcher.rawValue) fix details")
            }
        }
    }

    func testGPUSpoofOmitsUnreadVariables() {
        for vendor in GPUVendor.allCases {
            let env = GPUDetection.spoofGPU(vendor: vendor, model: "Custom GPU")
            for name in unreadVariables {
                XCTAssertNil(env[name], "\(name) in \(vendor.rawValue) spoof")
            }
            // D3DMetal reads this one, so it stays.
            XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
        }
    }

    func testGameDatabaseOmitsUnreadVariables() {
        for entry in GameDBLoader.loadDefaults() {
            for variant in entry.variants {
                let env = variant.environmentVariables ?? [:]
                for name in unreadVariables {
                    XCTAssertNil(env[name], "\(name) in \(entry.id)/\(variant.id)")
                }
            }
        }
    }
}
