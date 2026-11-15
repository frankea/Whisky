//
//  BackendEnvironmentTests.swift
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
import Testing
@testable import WhiskyKit

/// The variables a setting has to set for the translation layer that is
/// actually running to read it (Dunn-Kim/Whisky).
@Suite("Backend environment variables")
struct BackendEnvironmentTests {
    /// The environment a program sees: the bottle layer with the program's
    /// overrides applied on top.
    private func environment(
        _ settings: BottleSettings, _ overrides: ProgramOverrides = ProgramOverrides()
    ) -> [String: String] {
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        _ = settings.populateBottleManagedLayer(
            builder: &builder, resolvedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false
        )
        Wine.applyProgramOverrides(
            overrides, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: false,
            builder: &builder, dllResolver: &dllResolver
        )
        return builder.resolve().environment
    }

    // MARK: - Shader cache

    @Test("Turning the shader cache off reaches DXMT as well as DXVK", arguments: GraphicsBackend.allCases)
    func disabledShaderCacheSetsBothVariables(backend: GraphicsBackend) {
        var settings = BottleSettings()
        settings.graphicsBackend = backend
        settings.shaderCacheEnabled = false

        let env = environment(settings)
        #expect(env["DXVK_STATE_CACHE"] == "0")
        #expect(env["DXMT_SHADER_CACHE"] == "0")
    }

    @Test("The shader cache left on sets neither variable")
    func enabledShaderCacheSetsNothing() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt

        let env = environment(settings)
        #expect(env["DXVK_STATE_CACHE"] == nil)
        #expect(env["DXMT_SHADER_CACHE"] == nil)
    }

    @Test("A program can turn DXMT's shader cache off, or back on over the bottle")
    func programShaderCacheOverride() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt
        var disabled = ProgramOverrides()
        disabled.shaderCacheEnabled = false
        #expect(environment(settings, disabled)["DXMT_SHADER_CACHE"] == "0")

        settings.shaderCacheEnabled = false
        var enabled = ProgramOverrides()
        enabled.shaderCacheEnabled = true
        let env = environment(settings, enabled)
        #expect(env["DXMT_SHADER_CACHE"] == nil)
        #expect(env["DXVK_STATE_CACHE"] == nil)
    }

    @Test("A program moved onto DXMT keeps the bottle's disabled cache")
    func programMovedOntoDXMTKeepsDisabledCache() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        settings.shaderCacheEnabled = false
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxmt

        #expect(environment(settings, overrides)["DXMT_SHADER_CACHE"] == "0")
    }
}
