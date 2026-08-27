//
//  EnvironmentVariablesTests.swift
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

// swiftlint:disable file_length
@testable import WhiskyKit
import XCTest

// swiftlint:disable:next type_body_length
final class EnvironmentVariablesTests: XCTestCase {
    // MARK: - DXVK Environment Variables

    func testEnvironmentVariablesWithDXVK() {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.dxvkHud = .full

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // DLL overrides are now composed per-DLL via DLLOverrideResolver (sorted alphabetically)
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=n,b;dxgi=n,b")
        XCTAssertEqual(env["DXVK_HUD"], "full")
    }

    // MARK: - DXMT Environment Variables

    func testEnvironmentVariablesWithDXMT() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // The trio is native-then-builtin; winemetal pinned builtin for unixlib binding.
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10core=n,b;d3d11=n,b;d3d12=;dxgi=n,b;winemetal=b")
        // DXMT is not DXVK and not wined3d: none of their env vars may leak.
        XCTAssertNil(env["DXVK_HUD"])
        XCTAssertNil(env["DXVK_ASYNC"])
        XCTAssertNil(env["WINED3DMETAL"])
    }

    func testDXVKSettingsDoNotApplyUnderDXMT() {
        // dxvkHud/dxvkAsync persist in dxvkConfig but only take effect when the
        // backend is DXVK.
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt
        settings.dxvkHud = .full
        settings.dxvkAsync = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertNil(env["DXVK_HUD"])
        XCTAssertNil(env["DXVK_ASYNC"])
    }

    func testEnvironmentVariablesWithDXVKHUDPartial() {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.dxvkHud = .partial

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_HUD"], "devinfo,fps,frametimes")
    }

    func testEnvironmentVariablesWithDXVKHUDFPS() {
        var settings = BottleSettings()
        settings.dxvk = true
        settings.dxvkHud = .fps

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_HUD"], "fps")
    }

    func testEnvironmentVariablesWithDXVKAsync() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        settings.dxvkAsync = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_ASYNC"], "1")
    }

    // MARK: - Enhanced Sync Environment Variables

    func testEnvironmentVariablesWithESyncOnly() {
        var settings = BottleSettings()
        settings.enhancedSync = .esync

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["WINEESYNC"], "1")
        XCTAssertNil(env["WINEMSYNC"])
    }

    func testEnvironmentVariablesWithMSync() {
        var settings = BottleSettings()
        settings.enhancedSync = .msync

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // When MSync is enabled, both WINEMSYNC and WINEESYNC must be set.
        // This is required for D3DM compatibility - values are hardcoded in lid3dshared.dylib
        XCTAssertEqual(env["WINEMSYNC"], "1")
        XCTAssertEqual(env["WINEESYNC"], "1")
    }

    func testEnvironmentVariablesWithNoEnhancedSync() {
        var settings = BottleSettings()
        settings.enhancedSync = .none

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        if MacOSVersion.current >= .sequoia15_4 {
            XCTAssertEqual(env["WINEESYNC"], "1")
            XCTAssertNil(env["WINEMSYNC"])
        } else {
            XCTAssertNil(env["WINEESYNC"])
            XCTAssertNil(env["WINEMSYNC"])
        }
    }

    // MARK: - Metal Environment Variables

    func testEnvironmentVariablesWithMetalHUD() {
        var settings = BottleSettings()
        settings.metalHud = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_HUD_ENABLED"], "1")
    }

    func testEnvironmentVariablesWithMetalTrace() {
        var settings = BottleSettings()
        settings.metalTrace = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["METAL_CAPTURE_ENABLED"], "1")
    }

    func testEnvironmentVariablesWithMetalValidation() {
        var settings = BottleSettings()
        settings.metalValidation = true
        settings.sequoiaCompatMode = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "1")
    }

    // MARK: - Other Environment Variables

    func testEnvironmentVariablesWithAVX() {
        var settings = BottleSettings()
        settings.avxEnabled = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["ROSETTA_ADVERTISE_AVX"], "1")
    }

    func testEnvironmentVariablesWithDXR() {
        var settings = BottleSettings()
        settings.dxrEnabled = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
    }

    func testSpoofDoesNotOutbidForceD3D11() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.gpuSpoofing = true
        settings.forceD3D11 = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Feature level is one resolved decision: the spoof's launcher layer
        // must not undo the force-D3D11 pin from the bottle layer.
        XCTAssertEqual(env["D3DM_FEATURE_LEVEL_12_0"], "0")
        XCTAssertNil(env["D3DM_FEATURE_LEVEL_12_1"])
    }

    // MARK: - Sequoia Compatibility Mode

    func testSequoiaToggleEmitsNothing() {
        var settings = BottleSettings()
        settings.sequoiaCompatMode = true
        settings.metalValidation = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // All three values the toggle used to set are platform-layer fixes on
        // every supported macOS, carried with provenance by
        // constructWineEnvironment; the bottle-layer duplicates meant the
        // toggle's off position changed nothing.
        XCTAssertNil(env["MTL_DEBUG_LAYER"])
        XCTAssertNil(env["D3DM_VALIDATION"])
        XCTAssertNil(env["WINEFSYNC"])
    }

    @MainActor
    func testPlatformLayerCarriesTheSequoiaFixes() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)

        let env = Wine.constructWineEnvironment(for: bottle)

        // Supported macOS is 15.4+ at minimum, so all three fixes apply.
        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "0")
        XCTAssertEqual(env["D3DM_VALIDATION"], "0")
        XCTAssertEqual(env["WINEFSYNC"], "0")
    }

    // MARK: - Performance Preset Environment Variables

    func testEnvironmentVariablesWithPerformancePreset() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        settings.performancePreset = .performance
        settings.sequoiaCompatMode = false // Disable to test performance preset in isolation

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Performance preset - prioritize FPS over visual quality
        XCTAssertEqual(env["D3DM_VALIDATION"], "0")
        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "0")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
        XCTAssertEqual(env["DXVK_SHADER_OPT_LEVEL"], "0")
        XCTAssertEqual(env["MTL_ENABLE_METAL_EVENTS"], "0")
    }

    func testEnvironmentVariablesWithQualityPreset() {
        var settings = BottleSettings()
        settings.performancePreset = .quality
        settings.sequoiaCompatMode = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["DXVK_SHADER_OPT_LEVEL"], "2")
    }

    func testEnvironmentVariablesWithUnityPreset() {
        var settings = BottleSettings()
        settings.performancePreset = .unity
        settings.sequoiaCompatMode = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Unity preset - il2cpp and threading optimizations
        XCTAssertEqual(env["MONO_THREADS_SUSPEND"], "1")
        XCTAssertEqual(env["WINE_LARGE_ADDRESS_AWARE"], "65536")
        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
        XCTAssertEqual(env["WINE_DISABLE_NTDLL_THREAD_REGS"], "1")
        XCTAssertEqual(env["WINEPRELOADRESERVE"], "1")
    }

    // MARK: - D3D11 and Shader Cache

    func testEnvironmentVariablesWithForceD3D11() {
        var settings = BottleSettings()
        settings.forceD3D11 = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["D3DM_FORCE_D3D11"], "1")
        XCTAssertEqual(env["D3DM_FEATURE_LEVEL_12_0"], "0")
    }

    func testEnvironmentVariablesWithDisabledShaderCache() {
        var settings = BottleSettings()
        settings.shaderCacheEnabled = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // The variable DXVK reads, not the NVIDIA GL one the toggle used to set.
        XCTAssertEqual(env["DXVK_STATE_CACHE"], "0")
        XCTAssertNil(env["DXVK_SHADER_COMPILE_THREADS"])
        XCTAssertNil(env["__GL_SHADER_DISK_CACHE"])
    }

    // MARK: - EnvironmentBuilder Layer Populator Tests

    func testPopulateBottleManagedLayerReturnsDXVKOverrides() {
        var settings = BottleSettings()
        settings.dxvk = true

        var builder = EnvironmentBuilder()
        let managedOverrides = settings.populateBottleManagedLayer(builder: &builder)

        // DXVK managed overrides should be returned, not set via builder
        XCTAssertEqual(managedOverrides.count, 5) // dxgi, d3d9, d3d10core, d3d11, d3d12
        XCTAssertTrue(managedOverrides.allSatisfy { $0.source == .dxvk })

        // WINEDLLOVERRIDES should NOT be in the resolved environment (handled by DLLOverrideResolver)
        let (resolved, _) = builder.resolve()
        XCTAssertNil(resolved["WINEDLLOVERRIDES"])
    }

    func testPopulateBottleManagedLayerNoDXVKOverridesWhenDisabled() {
        // `dxvk = false` maps the backend to `.recommended`, whose ambient
        // resolution depends on the machine's installed runtime. Pin a
        // builtin-backed backend: this test is about the DXVK toggle being
        // off, not about resolution.
        var settings = BottleSettings()
        settings.dxvk = false

        var builder = EnvironmentBuilder()
        let managedOverrides = settings.populateBottleManagedLayer(
            builder: &builder, resolvedBackend: .d3dMetal
        )

        XCTAssertTrue(managedOverrides.isEmpty)
    }

    func testPopulateBottleManagedLayerRecommendedWithoutRuntimeAppliesDXVKPreset() {
        // On a machine with no installed runtime `.recommended` resolves to
        // DXVK, and the managed layer applies the DXVK preset even though the
        // legacy `dxvk` toggle is off — backend selection supersedes the
        // toggle, matching explicit `.dxvk` behavior.
        var settings = BottleSettings()
        settings.dxvk = false

        let resolved = GraphicsBackendResolver.resolve(runtimeInfo: nil, d3dMetalInstalled: false)
        XCTAssertEqual(resolved, .dxvk)

        var builder = EnvironmentBuilder()
        let managedOverrides = settings.populateBottleManagedLayer(
            builder: &builder, resolvedBackend: resolved
        )

        XCTAssertEqual(managedOverrides.count, 5) // dxgi, d3d9, d3d10core, d3d11, d3d12
        XCTAssertTrue(managedOverrides.allSatisfy { $0.source == .dxvk })
    }

    func testPopulateLauncherManagedLayerReturnsEmptyWhenDisabled() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = false

        var builder = EnvironmentBuilder()
        let launcherOverrides = settings.populateLauncherManagedLayer(builder: &builder)

        XCTAssertTrue(launcherOverrides.isEmpty)
        let (resolved, _) = builder.resolve()
        // No launcher-specific keys should be set
        XCTAssertNil(resolved["WINE_FORCE_HTTP11"])
    }

    // MARK: - Program Override Tests (applyProgramOverrides, direct)

    /// Runs the real `applyProgramOverrides` against a bottle-managed layer and
    /// returns the resolved WINEDLLOVERRIDES string.
    private func resolvedOverrides(
        bottleSettings: BottleSettings,
        programOverrides: ProgramOverrides
    ) -> String {
        var settings = bottleSettings
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        let managed = settings.populateBottleManagedLayer(builder: &builder)
        dllResolver.managed.append(contentsOf: managed)

        Wine.applyProgramOverrides(programOverrides, builder: &builder, dllResolver: &dllResolver)

        let (overrideString, _) = dllResolver.resolve()
        return overrideString
    }

    func testProgramBackendOverrideDXMTAppendsPreset() {
        // A D3DMetal bottle with a per-program DXMT override gets DXMT's overrides.
        // The full translation-DLL union is reset to builtin first, so d3d9 (which
        // DXMT's preset doesn't touch) is pinned to builtin.
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxmt

        let resolved = resolvedOverrides(bottleSettings: settings, programOverrides: overrides)
        XCTAssertEqual(resolved, "d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=b;dxgi=n,b;winemetal=b")
    }

    func testProgramBackendOverrideDXMTNeutralizesLeakedDXVKd3d9() {
        // Regression: a DXVK bottle (whose managed layer enables d3d9=n,b and
        // whose prefix has a stale native DXVK d3d9.dll) with a per-program DXMT
        // override must force d3d9 back to builtin — otherwise a D3D9 title runs
        // under the leaked DXVK d3d9 instead of the DXMT selection.
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxmt

        let resolved = resolvedOverrides(bottleSettings: settings, programOverrides: overrides)
        XCTAssertEqual(resolved, "d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=b;dxgi=n,b;winemetal=b")
        XCTAssertFalse(resolved.contains("d3d9=n,b"), "Leaked DXVK d3d9 must be reset to builtin")
    }

    func testProgramBackendOverrideD3DMetalResetsDXMT() {
        // A DXMT bottle with a per-program D3DMetal override must reset every
        // translation DLL (the dxvk+dxmt union) back to builtin.
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .d3dMetal

        let resolved = resolvedOverrides(bottleSettings: settings, programOverrides: overrides)
        for dll in ["d3d10core", "d3d11", "dxgi"] {
            XCTAssertTrue(resolved.contains("\(dll)=b"), "\(dll) should be reset to builtin, got: \(resolved)")
            XCTAssertFalse(resolved.contains("\(dll)=n,b"), "\(dll) must not stay native, got: \(resolved)")
        }
    }

    func testLegacyDXVKFlagIgnoredWhenBackendOverridePresent() {
        // The program-override UI historically writes `dxvk` alongside
        // `graphicsBackend`. The legacy flag must not clobber the explicit
        // backend choice: dxvk=false with backend=.dxmt keeps DXMT active.
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxmt
        overrides.dxvk = false

        let resolved = resolvedOverrides(bottleSettings: settings, programOverrides: overrides)
        XCTAssertEqual(resolved, "d3d10core=n,b;d3d11=n,b;d3d12=;d3d9=b;dxgi=n,b;winemetal=b")
    }

    func testLegacyDXVKTrueDoesNotResurrectDXVKUnderD3DMetalOverride() {
        // Regression for the pre-existing clobber: backend=.d3dMetal with the
        // stale legacy dxvk=true must NOT re-enable DXVK's native overrides.
        var settings = BottleSettings()
        settings.dxvk = true

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .d3dMetal
        overrides.dxvk = true

        let resolved = resolvedOverrides(bottleSettings: settings, programOverrides: overrides)
        XCTAssertFalse(resolved.contains("d3d11=n,b"), "DXVK must stay disabled, got: \(resolved)")
        XCTAssertTrue(resolved.contains("d3d11=b"))
    }

    func testProgramOverrideDXVKFalseOverridesBottleDXVK() {
        var settings = BottleSettings()
        settings.dxvk = true // Bottle has DXVK enabled

        // Build with program overrides disabling DXVK
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])

        let managed = settings.populateBottleManagedLayer(builder: &builder)
        dllResolver.managed.append(contentsOf: managed)

        // Apply program override: dxvk = false
        var overrides = ProgramOverrides()
        overrides.dxvk = false

        // Simulate what constructWineEnvironment does for program overrides
        for entry in DLLOverrideResolver.dxvkPreset {
            dllResolver.programCustom.append(
                DLLOverrideEntry(dllName: entry.dllName, mode: .builtin)
            )
        }

        let (overrideString, _) = dllResolver.resolve()
        // Program forces builtin mode, overriding managed native-then-builtin
        XCTAssertTrue(overrideString.contains("dxgi=b"))
        XCTAssertTrue(overrideString.contains("d3d11=b"))
    }

    func testProgramOverrideEnhancedSyncOverridesBottle() {
        // Bottle has msync, program overrides to esync
        var builder = EnvironmentBuilder()
        builder.set("WINEMSYNC", "1", layer: .bottleManaged)
        builder.set("WINEESYNC", "1", layer: .bottleManaged)

        // Program overrides to esync only
        builder.set("WINEESYNC", "1", layer: .programUser)
        builder.remove("WINEMSYNC", layer: .programUser)

        let (resolved, _) = builder.resolve()
        XCTAssertEqual(resolved["WINEESYNC"], "1")
        XCTAssertNil(resolved["WINEMSYNC"]) // Removed by programUser layer
    }

    func testDLLOverridesComposeCorrectly() {
        // Bottle DXVK on + program custom DLL override -> both present in WINEDLLOVERRIDES
        var dllResolver = DLLOverrideResolver(
            managed: DLLOverrideResolver.dxvkPreset.map { (entry: $0, source: DLLOverrideSource.dxvk) },
            bottleCustom: [],
            programCustom: [DLLOverrideEntry(dllName: "xaudio2_7", mode: .native)]
        )

        let (overrideString, _) = dllResolver.resolve()
        // Both DXVK DLLs and the custom override should be present
        XCTAssertTrue(overrideString.contains("dxgi=n,b"))
        XCTAssertTrue(overrideString.contains("d3d11=n,b"))
        XCTAssertTrue(overrideString.contains("xaudio2_7=n"))
    }

    func testProgramOverrideDXVKAsyncSetsInProgramUserLayer() {
        var builder = EnvironmentBuilder()
        // Bottle managed sets DXVK_ASYNC=1
        builder.set("DXVK_ASYNC", "1", layer: .bottleManaged)
        // Program override disables it
        builder.set("DXVK_ASYNC", "0", layer: .programUser)

        let (resolved, _) = builder.resolve()
        // programUser wins over bottleManaged
        XCTAssertEqual(resolved["DXVK_ASYNC"], "0")
    }

    // MARK: - hardware scheduling is claimed only where it applies

    func testD3DMetalBottleClaimsHardwareScheduling() {
        // Wine answers the WDDM 2.7 caps query only for a caller that says it is
        // on D3DMetal; without it, a game asking about GPU scheduling is told
        // the feature is not implemented.
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal
        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)
        XCTAssertEqual(env["CX_ACTIVE_GRAPHICS_BACKEND"], "d3dmetal")
    }

    func testDXVKBottleDoesNotClaimHardwareScheduling() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)
        XCTAssertNil(env["CX_ACTIVE_GRAPHICS_BACKEND"])
    }

    /// Resolves the environment a program launch actually sees: the bottle-managed
    /// layer with the program override applied on top.
    private func resolvedEnvironment(
        bottleSettings: BottleSettings,
        programOverrides: ProgramOverrides
    ) -> [String: String] {
        var settings = bottleSettings
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        let managed = settings.populateBottleManagedLayer(builder: &builder)
        dllResolver.managed.append(contentsOf: managed)

        Wine.applyProgramOverrides(programOverrides, builder: &builder, dllResolver: &dllResolver)

        let (resolved, _) = builder.resolve()
        return resolved
    }

    func testDXVKProgramOverrideKeepsHardwareSchedulingClaim() {
        // Steam is steered onto DXVK so Chromium paints, and its games inherit that
        // environment. The variable answers a capability query rather than selecting
        // a backend, so stripping it here left every Steam-launched game unable to
        // turn on DLSS frame generation even though it ran on D3DMetal.
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxvk

        let env = resolvedEnvironment(bottleSettings: settings, programOverrides: overrides)
        XCTAssertEqual(env["CX_ACTIVE_GRAPHICS_BACKEND"], "d3dmetal")
    }

    func testDXMTProgramOverrideKeepsHardwareSchedulingClaim() {
        // DXMT translates d3d11 only, so d3d12 is still D3DMetal underneath.
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxmt

        let env = resolvedEnvironment(bottleSettings: settings, programOverrides: overrides)
        XCTAssertEqual(env["CX_ACTIVE_GRAPHICS_BACKEND"], "d3dmetal")
    }

    func testWineD3DProgramOverrideDropsHardwareSchedulingClaim() {
        // wined3d is the one override that switches D3DMetal off outright, so
        // there is nothing behind the claim.
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal

        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .wined3d

        let env = resolvedEnvironment(bottleSettings: settings, programOverrides: overrides)
        XCTAssertNil(env["CX_ACTIVE_GRAPHICS_BACKEND"])
    }
}
