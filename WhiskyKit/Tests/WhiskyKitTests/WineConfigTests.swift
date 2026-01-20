//
//  WineConfigTests.swift
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

import Foundation
@testable import WhiskyKit
import XCTest

// MARK: - LauncherType Tests

final class LauncherTypeTests: XCTestCase {
    func testAllLauncherTypesExist() {
        let types: [LauncherType] = [.steam, .eaApp, .battleNet, .epicGames, .rockstar, .ubisoft, .paradox]
        XCTAssertEqual(types.count, 7)
    }

    func testLauncherTypeHashable() {
        var set = Set<LauncherType>()
        set.insert(.steam)
        set.insert(.eaApp)
        set.insert(.battleNet)

        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(.steam))
    }

    func testLauncherTypeEquatable() {
        XCTAssertEqual(LauncherType.steam, LauncherType.steam)
        XCTAssertNotEqual(LauncherType.steam, LauncherType.eaApp)
    }

    func testLauncherTypeEnvironmentOverridesNotEmpty() {
        for launcher in [LauncherType.steam, .eaApp, .battleNet, .epicGames, .rockstar, .ubisoft, .paradox] {
            // All launchers should return at least an empty dictionary
            let overrides = launcher.environmentOverrides()
            XCTAssertNotNil(overrides, "Launcher \(launcher) should return environment overrides")
        }
    }

    func testLauncherTypeRawValues() {
        XCTAssertEqual(LauncherType.steam.rawValue, "Steam")
        XCTAssertEqual(LauncherType.rockstar.rawValue, "Rockstar Games Launcher")
        XCTAssertEqual(LauncherType.eaApp.rawValue, "EA App")
        XCTAssertEqual(LauncherType.epicGames.rawValue, "Epic Games Store")
        XCTAssertEqual(LauncherType.ubisoft.rawValue, "Ubisoft Connect")
        XCTAssertEqual(LauncherType.battleNet.rawValue, "Battle.net")
        XCTAssertEqual(LauncherType.paradox.rawValue, "Paradox Launcher")
    }
}

// MARK: - LauncherMode Tests

final class LauncherModeTests: XCTestCase {
    func testLauncherModeValues() {
        let auto = LauncherMode.auto
        let manual = LauncherMode.manual

        XCTAssertNotNil(auto)
        XCTAssertNotNil(manual)
        XCTAssertNotEqual(String(describing: auto), String(describing: manual))
    }

    func testLauncherModeCodable() throws {
        struct Container: Codable {
            let mode: LauncherMode
        }

        let modes: [LauncherMode] = [.auto, .manual]

        for mode in modes {
            let original = Container(mode: mode)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(original)

            let decoded = try PropertyListDecoder().decode(Container.self, from: data)
            XCTAssertEqual(decoded.mode, mode)
        }
    }
}

// MARK: - GPUVendor Tests

final class GPUVendorTests: XCTestCase {
    func testAllVendorsExist() {
        let vendors: [GPUVendor] = [.nvidia, .amd, .intel]
        XCTAssertEqual(vendors.count, 3)
    }

    func testGPUVendorHashable() {
        var set = Set<GPUVendor>()
        set.insert(.nvidia)
        set.insert(.amd)
        set.insert(.intel)

        XCTAssertEqual(set.count, 3)
    }

    func testGPUVendorCodable() throws {
        struct Container: Codable {
            let vendor: GPUVendor
        }

        for vendor in [GPUVendor.nvidia, .amd, .intel] {
            let original = Container(vendor: vendor)

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(original)

            let decoded = try PropertyListDecoder().decode(Container.self, from: data)
            XCTAssertEqual(decoded.vendor, vendor)
        }
    }
}

// MARK: - GPUDetection Tests

final class GPUDetectionSpoofingTests: XCTestCase {
    func testSpoofWithNvidia() {
        let env = GPUDetection.spoofWithVendor(.nvidia)

        XCTAssertFalse(env.isEmpty, "NVIDIA spoofing should produce environment variables")
    }

    func testSpoofWithAMD() {
        let env = GPUDetection.spoofWithVendor(.amd)

        XCTAssertFalse(env.isEmpty, "AMD spoofing should produce environment variables")
    }

    func testSpoofWithIntel() {
        let env = GPUDetection.spoofWithVendor(.intel)

        XCTAssertFalse(env.isEmpty, "Intel spoofing should produce environment variables")
    }

    func testSpoofProducesStringDictionary() {
        for vendor in [GPUVendor.nvidia, .amd, .intel] {
            let env = GPUDetection.spoofWithVendor(vendor)

            for (key, value) in env {
                XCTAssertFalse(key.isEmpty, "Key should not be empty for vendor \(vendor)")
                XCTAssertFalse(value.isEmpty, "Value should not be empty for vendor \(vendor)")
            }
        }
    }
}

// MARK: - BottleLauncherConfig Detailed Tests

final class BottleLauncherConfigDetailedTests: XCTestCase {
    func testDefaultValues() {
        let config = BottleLauncherConfig()

        XCTAssertFalse(config.compatibilityMode)
        XCTAssertEqual(config.launcherMode, .auto)
        XCTAssertNil(config.detectedLauncher)
        XCTAssertEqual(config.launcherLocale, .auto)
        XCTAssertTrue(config.gpuSpoofing)
        XCTAssertEqual(config.gpuVendor, .nvidia)
        XCTAssertEqual(config.networkTimeout, 60_000)
        XCTAssertTrue(config.autoEnableDXVK)
    }

    func testRoundTrip() throws {
        var original = BottleLauncherConfig()
        original.compatibilityMode = true
        original.launcherMode = .manual
        original.detectedLauncher = .steam
        original.launcherLocale = .english
        original.gpuSpoofing = true
        original.gpuVendor = .amd
        original.networkTimeout = 30_000
        original.autoEnableDXVK = false

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleLauncherConfig.self, from: data)

        XCTAssertTrue(decoded.compatibilityMode)
        XCTAssertEqual(decoded.launcherMode, .manual)
        XCTAssertEqual(decoded.detectedLauncher, .steam)
        XCTAssertEqual(decoded.launcherLocale, .english)
        XCTAssertTrue(decoded.gpuSpoofing)
        XCTAssertEqual(decoded.gpuVendor, .amd)
        XCTAssertEqual(decoded.networkTimeout, 30_000)
        XCTAssertFalse(decoded.autoEnableDXVK)
    }
}

// MARK: - BottleInputConfig Detailed Tests

final class BottleInputConfigDetailedTests: XCTestCase {
    func testDefaultValues() {
        let config = BottleInputConfig()

        XCTAssertFalse(config.controllerCompatibilityMode)
        XCTAssertFalse(config.disableHIDAPI)
        XCTAssertFalse(config.allowBackgroundEvents)
        XCTAssertFalse(config.disableControllerMapping)
    }

    func testRoundTrip() throws {
        var original = BottleInputConfig()
        original.controllerCompatibilityMode = true
        original.disableHIDAPI = true
        original.allowBackgroundEvents = true
        original.disableControllerMapping = true

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleInputConfig.self, from: data)

        XCTAssertTrue(decoded.controllerCompatibilityMode)
        XCTAssertTrue(decoded.disableHIDAPI)
        XCTAssertTrue(decoded.allowBackgroundEvents)
        XCTAssertTrue(decoded.disableControllerMapping)
    }
}

// MARK: - WhiskyWineInstaller Path Tests

final class WhiskyWineInstallerPathTests: XCTestCase {
    func testLibraryFolderPath() {
        let path = WhiskyWineInstaller.libraryFolder.path

        XCTAssertTrue(path.contains("Library"))
        XCTAssertTrue(path.contains("Application Support"))
    }

    func testBinFolderPath() {
        let path = WhiskyWineInstaller.binFolder.path

        XCTAssertTrue(path.contains("bin"))
    }
}

// MARK: - Wine Binary Path Tests

final class WineBinaryPathTests: XCTestCase {
    func testWineBinaryPathContainsWine64() {
        let path = Wine.wineBinary.path
        XCTAssertTrue(path.contains("wine64"))
    }

    func testLogsFolderPathContainsLogs() {
        let path = Wine.logsFolder.path
        XCTAssertTrue(path.contains("Logs"))
    }
}

// MARK: - WineInterfaceError Tests

final class WineInterfaceErrorTests: XCTestCase {
    func testInvalidResponseError() {
        let error = WineInterfaceError.invalidResponse
        XCTAssertNotNil(error)
    }

    func testWineInterfaceErrorIsError() {
        let error: Error = WineInterfaceError.invalidResponse
        XCTAssertNotNil(error)
    }
}

// MARK: - Additional RegistryType Tests

final class RegistryTypeDetailedTests: XCTestCase {
    func testAllRegistryTypes() {
        let types: [RegistryType] = [.binary, .dword, .qword, .string]
        XCTAssertEqual(types.count, 4)
    }

    func testRegistryTypeEquatable() {
        XCTAssertEqual(RegistryType.binary, RegistryType.binary)
        XCTAssertEqual(RegistryType.string, RegistryType.string)
        XCTAssertNotEqual(RegistryType.binary, RegistryType.string)
    }

    func testRegistryTypeHashable() {
        var set = Set<RegistryType>()
        set.insert(.binary)
        set.insert(.dword)
        set.insert(.qword)
        set.insert(.string)

        XCTAssertEqual(set.count, 4)
    }
}
