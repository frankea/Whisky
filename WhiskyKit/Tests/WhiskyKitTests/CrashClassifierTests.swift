//
//  CrashClassifierTests.swift
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

final class CrashClassifierTests: XCTestCase {
    // MARK: - PatternLoader Tests

    func testLoadDefaultPatterns() {
        let (patterns, remediations) = PatternLoader.loadDefaults()
        XCTAssertGreaterThanOrEqual(patterns.count, 15, "Should load at least 15 patterns")
        XCTAssertGreaterThanOrEqual(remediations.count, 8, "Should load at least 8 remediation actions")
    }

    func testPatternsCoversAllCategories() {
        let (patterns, _) = PatternLoader.loadDefaults()
        let categories = Set(patterns.map(\.category))

        for category in CrashCategory.allCases {
            XCTAssertTrue(
                categories.contains(category),
                "Missing patterns for category: \(category.rawValue)"
            )
        }
    }

    // MARK: - ConfidenceTier Tests

    func testConfidenceTierHigh() {
        XCTAssertEqual(ConfidenceTier(score: 0.9), .high)
        XCTAssertEqual(ConfidenceTier(score: 0.8), .high)
        XCTAssertEqual(ConfidenceTier(score: 1.0), .high)
    }

    func testConfidenceTierMedium() {
        XCTAssertEqual(ConfidenceTier(score: 0.6), .medium)
        XCTAssertEqual(ConfidenceTier(score: 0.5), .medium)
        XCTAssertEqual(ConfidenceTier(score: 0.79), .medium)
    }

    func testConfidenceTierLow() {
        XCTAssertEqual(ConfidenceTier(score: 0.3), .low)
        XCTAssertEqual(ConfidenceTier(score: 0.0), .low)
        XCTAssertEqual(ConfidenceTier(score: 0.49), .low)
    }

    func testConfidenceTierComparable() {
        XCTAssertTrue(ConfidenceTier.low < ConfidenceTier.medium)
        XCTAssertTrue(ConfidenceTier.medium < ConfidenceTier.high)
        XCTAssertFalse(ConfidenceTier.high < ConfidenceTier.low)
    }

    // MARK: - CrashCategory Tests

    func testCrashCategoryDisplayNames() {
        for category in CrashCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "Display name should not be empty for \(category)")
            XCTAssertFalse(category.sfSymbol.isEmpty, "SF Symbol should not be empty for \(category)")
        }
    }

    // MARK: - PatternSeverity Tests

    func testPatternSeverityOrdering() {
        XCTAssertTrue(PatternSeverity.info < PatternSeverity.warning)
        XCTAssertTrue(PatternSeverity.warning < PatternSeverity.error)
        XCTAssertTrue(PatternSeverity.error < PatternSeverity.critical)
    }

    // MARK: - CrashPattern Match Tests

    func testDLLLoadFailureMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line =
            "0024:err:module:import_dll Library MSVCR100.dll (which is needed by L\"game.exe\") not found"

        var matched = false
        for index in patterns.indices where patterns[index].id == "dll-load-failure" {
            if let result = patterns[index].match(line: line) {
                matched = true
                XCTAssertEqual(result.captures.first, "MSVCR100.dll")
                XCTAssertEqual(patterns[index].category, .dependenciesLoading)
            }
        }
        XCTAssertTrue(matched, "dll-load-failure pattern should match")
    }

    func testPrefilterSkipsRegex() {
        var pattern = CrashPattern(
            id: "test-prefilter",
            category: .dependenciesLoading,
            severity: .error,
            confidence: 0.9,
            substringPrefilter: "import_dll",
            regex: "err:module:import_dll Library (\\S+\\.dll).*not found",
            tags: [],
            captureGroups: nil,
            remediationActionIds: nil
        )

        // This line does NOT contain "import_dll", so prefilter should skip regex
        let unrelatedLine = "fixme:d3d:something unrelated"
        let result = pattern.match(line: unrelatedLine)
        XCTAssertNil(result, "Prefilter should skip regex for unrelated lines")
    }

    func testAccessViolationMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line =
            "0080:err:seh:NtRaiseException Unhandled exception code c0000005 flags 0 addr 0x7b012345"

        var matched = false
        for index in patterns.indices {
            if patterns[index].id == "access-violation" || patterns[index].id == "nt-raise-exception" {
                if patterns[index].match(line: line) != nil {
                    matched = true
                    XCTAssertEqual(patterns[index].category, .coreCrashFatal)
                }
            }
        }
        XCTAssertTrue(matched, "Access violation line should match a coreCrashFatal pattern")
    }

    func testPageFaultMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line = "wine: Unhandled page fault on read access to 0x00000000 at address 0x7b012345"

        var matched = false
        for index in patterns.indices where patterns[index].id == "page-fault" {
            if patterns[index].match(line: line) != nil {
                matched = true
                XCTAssertEqual(patterns[index].category, .coreCrashFatal)
            }
        }
        XCTAssertTrue(matched, "Page fault line should match")
    }

    func testGPUDeviceLostMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line = "err:d3d11:device_lost D3D11 device lost (DXGI_ERROR_DEVICE_REMOVED)"

        var matched = false
        for index in patterns.indices where patterns[index].id == "gpu-device-lost-dxvk" {
            if patterns[index].match(line: line) != nil {
                matched = true
                XCTAssertEqual(patterns[index].category, .graphics)
            }
        }
        XCTAssertTrue(matched, "GPU device lost line should match")
    }

    func testAntiCheatEACMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line = "EasyAntiCheat.exe: Fatal error - EasyAntiCheat is not installed"

        var matched = false
        for index in patterns.indices where patterns[index].id == "anticheat-eac" {
            if patterns[index].match(line: line) != nil {
                matched = true
                XCTAssertEqual(patterns[index].category, .antiCheatUnsupported)
            }
        }
        XCTAssertTrue(matched, "EasyAntiCheat line should match")
    }

    func testAntiCheatBattlEyeMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line = "BattlEye Service: error initializing - BattlEye not supported on this platform"

        var matched = false
        for index in patterns.indices where patterns[index].id == "anticheat-battleye" {
            if patterns[index].match(line: line) != nil {
                matched = true
                XCTAssertEqual(patterns[index].category, .antiCheatUnsupported)
            }
        }
        XCTAssertTrue(matched, "BattlEye line should match")
    }

    func testDotNetCLRMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line =
            "0024:err:module:import_dll Library mscoree.dll (which is needed by L\"app.exe\") not found"

        var matched = false
        for index in patterns.indices {
            if patterns[index].id == "dotnet-clr-missing" || patterns[index].id == "dll-load-failure" {
                if let result = patterns[index].match(line: line) {
                    matched = true
                    // Both patterns may match -- at least one should be dependenciesLoading
                    XCTAssertEqual(patterns[index].category, .dependenciesLoading)
                    if patterns[index].id == "dll-load-failure" {
                        XCTAssertEqual(result.captures.first, "mscoree.dll")
                    }
                }
            }
        }
        XCTAssertTrue(matched, ".NET CLR line should match")
    }

    func testPrefixCorruptionMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line = "wine: could not load user32.dll, status c0000135"

        var matched = false
        for index in patterns.indices where patterns[index].id == "prefix-corruption" {
            if patterns[index].match(line: line) != nil {
                matched = true
                XCTAssertEqual(patterns[index].category, .prefixFilesystem)
            }
        }
        XCTAssertTrue(matched, "Prefix corruption line should match")
    }

    func testNetworkTLSMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()
        let line = "0024:err:winhttp:request_send_request secure connection failed"

        var matched = false
        for index in patterns.indices where patterns[index].id == "network-winhttp-tls" {
            if patterns[index].match(line: line) != nil {
                matched = true
                XCTAssertEqual(patterns[index].category, .networkingLaunchers)
            }
        }
        XCTAssertTrue(matched, "Network TLS line should match")
    }

    // MARK: - CrashDiagnosis Remediation Tests

    func testDiagnosisRemediationResolution() {
        let (_, remediations) = PatternLoader.loadDefaults()

        let pattern = CrashPattern(
            id: "test",
            category: .dependenciesLoading,
            severity: .error,
            confidence: 0.9,
            substringPrefilter: nil,
            regex: "test",
            tags: [],
            captureGroups: nil,
            remediationActionIds: ["install-vcredist", "install-dotnet"]
        )

        let diagMatch = DiagnosisMatch(
            pattern: pattern,
            lineIndex: 0,
            lineText: "test line",
            captures: []
        )

        let diagnosis = CrashDiagnosis(
            matches: [diagMatch],
            categoryCounts: [.dependenciesLoading: 1],
            primaryCategory: .dependenciesLoading,
            primaryConfidence: .high,
            headline: "Missing DLL",
            exitCode: nil,
            applicableRemediationIds: ["install-vcredist", "install-dotnet"]
        )

        let resolved = diagnosis.remediations(from: remediations)
        XCTAssertEqual(resolved.count, 2)
        XCTAssertTrue(resolved.contains { $0.id == "install-vcredist" })
        XCTAssertTrue(resolved.contains { $0.id == "install-dotnet" })
    }

    func testEmptyDiagnosis() {
        let diagnosis = CrashDiagnosis(
            matches: [],
            categoryCounts: [:],
            primaryCategory: nil,
            primaryConfidence: nil,
            headline: nil,
            exitCode: 0,
            applicableRemediationIds: []
        )
        XCTAssertTrue(diagnosis.isEmpty)
    }

    // MARK: - RemediationAction Tests

    func testRemediationActionTypes() {
        let (_, remediations) = PatternLoader.loadDefaults()

        // Verify at least one of each action type exists
        let types = Set(remediations.values.map(\.actionType))
        XCTAssertTrue(types.contains(.installVerb))
        XCTAssertTrue(types.contains(.informational))
        XCTAssertTrue(types.contains(.switchBackend))
        XCTAssertTrue(types.contains(.changeSetting))
    }

    // MARK: - Every Pattern Positive Match

    // MARK: - CrashClassifier Pipeline Tests

    func testClassifyEmptyLog() {
        let classifier = CrashClassifier()
        let diagnosis = classifier.classify(log: "", exitCode: 0)
        XCTAssertTrue(diagnosis.isEmpty)
        XCTAssertNil(diagnosis.primaryCategory)
        XCTAssertNil(diagnosis.primaryConfidence)
        XCTAssertEqual(diagnosis.exitCode, 0)
        XCTAssertTrue(diagnosis.applicableRemediationIds.isEmpty)
    }

    func testClassifyDLLLoadFailure() {
        let classifier = CrashClassifier()
        let log = """
        0024:fixme:ntdll:NtQuerySystemInformation info_class SYSTEM_PERFORMANCE_INFORMATION
        0024:err:module:import_dll Library MSVCR100.dll (which is needed by L"game.exe") not found
        0024:fixme:ver:GetCurrentPackageId stub
        """
        let diagnosis = classifier.classify(log: log, exitCode: 1)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .dependenciesLoading)
        XCTAssertEqual(diagnosis.primaryConfidence, .high)
        XCTAssertEqual(diagnosis.exitCode, 1)

        // Should have captures with DLL name
        let dllMatch = diagnosis.matches.first { $0.pattern.id == "dll-load-failure" }
        XCTAssertNotNil(dllMatch)
        XCTAssertEqual(dllMatch?.captures.first, "MSVCR100.dll")
    }

    func testClassifyAccessViolation() {
        let classifier = CrashClassifier()
        let log = """
        0080:err:seh:NtRaiseException Unhandled exception code c0000005 flags 0 addr 0x7b012345
        """
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .coreCrashFatal)
        XCTAssertEqual(diagnosis.primaryConfidence, .high)
    }

    func testClassifyPageFault() {
        let classifier = CrashClassifier()
        let log = "wine: Unhandled page fault on read access to 0x00000000 at address 0x7b012345"
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .coreCrashFatal)
        XCTAssertEqual(diagnosis.primaryConfidence, .high)
    }

    func testClassifyGPUDeviceLost() {
        let classifier = CrashClassifier()
        let log = "err:d3d11:device_lost D3D11 device lost (DXGI_ERROR_DEVICE_REMOVED)"
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .graphics)
        XCTAssertEqual(diagnosis.primaryConfidence, .medium)
    }

    func testClassifyAntiCheat() {
        let classifier = CrashClassifier()
        let log = "EasyAntiCheat.exe: Fatal error - EasyAntiCheat is not installed"
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .antiCheatUnsupported)
        XCTAssertEqual(diagnosis.primaryConfidence, .high)
    }

    func testClassifyDotNetCLR() {
        let classifier = CrashClassifier()
        let log =
            "0024:err:module:import_dll Library mscoree.dll (which is needed by L\"app.exe\") not found"
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .dependenciesLoading)
        XCTAssertEqual(diagnosis.primaryConfidence, .high)

        // Both dll-load-failure and dotnet-clr-missing may match
        let matchIDs = Set(diagnosis.matches.map(\.pattern.id))
        XCTAssertTrue(matchIDs.contains("dll-load-failure") || matchIDs.contains("dotnet-clr-missing"))
    }

    func testClassifyPrefixCorruption() {
        let classifier = CrashClassifier()
        let log = "wine: could not load user32.dll, status c0000135"
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .prefixFilesystem)
        XCTAssertEqual(diagnosis.primaryConfidence, .medium)
    }

    func testClassifyNetworkTLS() {
        let classifier = CrashClassifier()
        let log = "0024:err:winhttp:request_send_request secure connection failed"
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.isEmpty)
        XCTAssertEqual(diagnosis.primaryCategory, .networkingLaunchers)
        XCTAssertEqual(diagnosis.primaryConfidence, .medium)
    }

    func testClassifyMultipleMatchesSortedByConfidence() {
        let classifier = CrashClassifier()
        // Log with multiple error types: anti-cheat (0.99 confidence) should be primary
        let log = """
        wine: could not load user32.dll, status c0000135
        EasyAntiCheat.exe: Fatal error - EasyAntiCheat is not installed
        err:d3d11:device_lost D3D11 device lost (DXGI_ERROR_DEVICE_REMOVED)
        """
        let diagnosis = classifier.classify(log: log, exitCode: 1)
        XCTAssertFalse(diagnosis.isEmpty)

        // Anti-cheat has highest confidence (0.99), should be primary
        XCTAssertEqual(diagnosis.primaryCategory, .antiCheatUnsupported)
        XCTAssertEqual(diagnosis.primaryConfidence, .high)

        // Should have matches from multiple categories
        XCTAssertGreaterThan(diagnosis.categoryCounts.count, 1)

        // Matches should be sorted by confidence DESC
        for index in 0 ..< diagnosis.matches.count - 1 {
            let current = diagnosis.matches[index].pattern.confidence
            let next = diagnosis.matches[index + 1].pattern.confidence
            XCTAssertGreaterThanOrEqual(current, next, "Matches should be sorted by confidence descending")
        }
    }

    func testClassifyPrefilterOptimization() {
        // Create a classifier with a pattern that has a prefilter
        let pattern = CrashPattern(
            id: "test-prefilter",
            category: .dependenciesLoading,
            severity: .error,
            confidence: 0.9,
            substringPrefilter: "import_dll",
            regex: "err:module:import_dll Library (\\S+\\.dll).*not found",
            tags: [],
            captureGroups: nil,
            remediationActionIds: nil
        )

        let classifier = CrashClassifier(patterns: [pattern], remediations: [:])

        // Log with no lines containing "import_dll" -- prefilter should skip all regex
        let log = """
        fixme:d3d:something unrelated
        fixme:ntdll:another thing
        warn:opengl:context init
        """
        let diagnosis = classifier.classify(log: log)
        XCTAssertTrue(diagnosis.isEmpty, "Prefilter should prevent any matches on unrelated lines")
    }

    func testClassifyRemediationIdsCollected() {
        let classifier = CrashClassifier()
        let log =
            "0024:err:module:import_dll Library MSVCR100.dll (which is needed by L\"game.exe\") not found"
        let diagnosis = classifier.classify(log: log)
        XCTAssertFalse(diagnosis.applicableRemediationIds.isEmpty, "Should have remediation IDs")

        // DLL load failure remediation IDs should include install-vcredist
        XCTAssertTrue(
            diagnosis.applicableRemediationIds.contains("install-vcredist"),
            "Should suggest installing vcredist"
        )
    }

    func testClassifyHeadlineGenerated() {
        let classifier = CrashClassifier()
        let log = "EasyAntiCheat.exe: Fatal error - EasyAntiCheat is not installed"
        let diagnosis = classifier.classify(log: log)
        XCTAssertNotNil(diagnosis.headline, "Should generate a headline")
        XCTAssertFalse(diagnosis.headline?.isEmpty ?? true, "Headline should not be empty")
    }

    // MARK: - WineDebugPreset Tests

    func testWineDebugPresetValues() {
        XCTAssertEqual(WineDebugPreset.normal.winedebugValue, "fixme-all")
        XCTAssertTrue(WineDebugPreset.crash.winedebugValue.contains("+seh"))
        XCTAssertTrue(WineDebugPreset.dllLoad.winedebugValue.contains("+loaddll"))
        XCTAssertEqual(WineDebugPreset.verbose.winedebugValue, "+all")
    }

    func testWineDebugPresetDisplayNames() {
        for preset in WineDebugPreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "Display name for \(preset) should not be empty")
            XCTAssertFalse(
                preset.presetDescription.isEmpty,
                "Description for \(preset) should not be empty"
            )
        }
    }

    func testWineDebugPresetCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for preset in WineDebugPreset.allCases {
            let data = try encoder.encode(preset)
            let decoded = try decoder.decode(WineDebugPreset.self, from: data)
            XCTAssertEqual(decoded, preset)
        }
    }

    func testWineDebugPresetAllCases() {
        XCTAssertEqual(WineDebugPreset.allCases.count, 4)
        XCTAssertTrue(WineDebugPreset.allCases.contains(.normal))
        XCTAssertTrue(WineDebugPreset.allCases.contains(.crash))
        XCTAssertTrue(WineDebugPreset.allCases.contains(.dllLoad))
        XCTAssertTrue(WineDebugPreset.allCases.contains(.verbose))
    }

    // MARK: - Every Pattern Positive Match

    func testEveryPatternHasPositiveMatch() {
        var (patterns, _) = PatternLoader.loadDefaults()

        // Sample log lines that should match each pattern
        let sampleLines: [String: String] = [
            "dll-load-failure":
                "0024:err:module:import_dll Library MSVCR100.dll (which is needed by L\"game.exe\") not found",
            "dll-load-d3dcompiler":
                "err:module:load_dll d3dcompiler_47.dll could not be loaded",
            "dll-load-d3dx9":
                "err:module:load_dll d3dx9_43.dll could not be loaded",
            "dll-load-xinput":
                "err:module:load_dll xinput1_3.dll could not be loaded",
            "dll-load-xaudio2":
                "err:module:load_dll xaudio2_7.dll could not be loaded",
            "dotnet-clr-missing":
                "0024:err:module:import_dll Library mscoree.dll (which is needed by L\"app.exe\") not found",
            "access-violation":
                "0080:err:seh:NtRaiseException Unhandled exception code c0000005 flags 0 addr 0x7b012345",
            "page-fault":
                "wine: Unhandled page fault on read access to 0x00000000 at address 0x7b012345",
            "nt-raise-exception":
                "err:seh:NtRaiseException Unhandled exception at 0x7b012345",
            "ldr-init-failure":
                "err:loader:LdrInitializeThunk Main thread failed to start",
            "gpu-device-lost-dxvk":
                "err:d3d11:device_lost D3D11 device lost (DXGI_ERROR_DEVICE_REMOVED)",
            "gpu-metal-validation":
                "Metal validation error: command buffer assertion failed",
            "gpu-d3d-device-hung":
                "D3D11: device hung during rendering",
            "dx12-path-issue":
                "DX12 feature not supported on this platform",
            "swapchain-failure":
                "err:vulkan:swapchain creation failed with error",
            "prefix-corruption":
                "wine: could not load user32.dll, status c0000135",
            "prefix-user-dirs-missing":
                "err:shell:init user dirs missing from prefix",
            "network-winhttp-tls":
                "err:winhttp:request_send_request secure connection failed",
            "network-http-timeout":
                "err:winhttp:send timed out waiting for server",
            "anticheat-eac":
                "EasyAntiCheat.exe: Fatal error - EasyAntiCheat is not installed",
            "anticheat-battleye":
                "BattlEye Service: error initializing - BattlEye not supported",
            "wine-nonzero-exit":
                "wine process exit code 1",
        ]

        for index in patterns.indices {
            let patternID = patterns[index].id
            guard let line = sampleLines[patternID] else {
                XCTFail("No sample line for pattern: \(patternID)")
                continue
            }

            let result = patterns[index].match(line: line)
            XCTAssertNotNil(result, "Pattern \(patternID) should match its sample line")
        }
    }
}
