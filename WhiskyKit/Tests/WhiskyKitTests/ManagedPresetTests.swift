//
//  ManagedPresetTests.swift
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

final class ManagedPresetTests: XCTestCase {
    func testDXVKBackendContributesTheDXVKPreset() {
        // d3d12 only where the builtin behind it is D3DMetal's; see DLLOverrideTests.
        let stock = DLLOverrideResolver.managedPreset(for: .dxvk, builtinD3D12IsD3DMetal: false)
        XCTAssertEqual(stock.map(\.dllName).sorted(), ["d3d10core", "d3d11", "d3d9", "dxgi"])
        let gptk = DLLOverrideResolver.managedPreset(for: .dxvk, builtinD3D12IsD3DMetal: true)
        XCTAssertEqual(gptk.map(\.dllName).sorted(), ["d3d10core", "d3d11", "d3d12", "d3d9", "dxgi"])
    }

    /// The case the config section used to miss entirely: a DXMT bottle applies
    /// four overrides at launch (five over D3DMetal's d3d12) and the UI listed
    /// none of them.
    func testDXMTBackendContributesTheDXMTPreset() {
        let stock = DLLOverrideResolver.managedPreset(for: .dxmt, builtinD3D12IsD3DMetal: false)
        XCTAssertEqual(stock.map(\.dllName).sorted(), ["d3d10core", "d3d11", "dxgi", "winemetal"])
        let gptk = DLLOverrideResolver.managedPreset(for: .dxmt, builtinD3D12IsD3DMetal: true)
        XCTAssertEqual(gptk.map(\.dllName).sorted(), ["d3d10core", "d3d11", "d3d12", "dxgi", "winemetal"])
    }

    /// D3DMetal and WineD3D both run on Wine's builtin D3D and pick between
    /// themselves with WINED3DMETAL, so neither overrides a DLL.
    func testBuiltinBackendsContributeNothing() {
        // Not even d3d12 over D3DMetal's builtin, which is theirs to use.
        XCTAssertTrue(DLLOverrideResolver.managedPreset(for: .d3dMetal, builtinD3D12IsD3DMetal: true).isEmpty)
        XCTAssertTrue(DLLOverrideResolver.managedPreset(for: .wined3d, builtinD3D12IsD3DMetal: true).isEmpty)
    }

    /// `.recommended` is not a backend, it is a deferral. Callers resolve it
    /// first; answering with a preset here would attribute one bottle's
    /// overrides to another machine's heuristics.
    func testRecommendedContributesNothingUnresolved() {
        XCTAssertTrue(DLLOverrideResolver.managedPreset(for: .recommended, builtinD3D12IsD3DMetal: true).isEmpty)
    }

    func testPresetMatchesWhatTheResolverApplies() {
        for backend in [GraphicsBackend.dxvk, .dxmt] {
            for builtinD3D12IsD3DMetal in [false, true] {
                let preset = DLLOverrideResolver.managedPreset(
                    for: backend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
                )
                let resolver = DLLOverrideResolver(
                    managed: preset.map { ($0, .dxvk) },
                    bottleCustom: [],
                    programCustom: []
                )
                let (overrides, _) = resolver.resolve()
                for entry in preset {
                    XCTAssertTrue(
                        overrides.contains("\(entry.dllName)=\(entry.mode.rawValue)"),
                        "\(backend.displayName) preset lost \(entry.dllName) through the resolver"
                    )
                }
            }
        }
    }
}
