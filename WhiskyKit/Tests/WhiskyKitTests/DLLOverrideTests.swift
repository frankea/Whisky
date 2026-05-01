//
//  DLLOverrideTests.swift
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

final class DLLOverrideTests: XCTestCase {
    // MARK: - DLL Override Mode

    func testDLLOverrideModeRawValues() {
        XCTAssertEqual(DLLOverrideMode.builtin.rawValue, "b")
        XCTAssertEqual(DLLOverrideMode.native.rawValue, "n")
        XCTAssertEqual(DLLOverrideMode.nativeThenBuiltin.rawValue, "n,b")
        XCTAssertEqual(DLLOverrideMode.builtinThenNative.rawValue, "b,n")
        XCTAssertEqual(DLLOverrideMode.disabled.rawValue, "")
    }

    // MARK: - DLL Override Entry Codable

    func testDLLOverrideEntryCodableRoundTrip() throws {
        let entry = DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(entry)
        let decoded = try PropertyListDecoder().decode(DLLOverrideEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    // MARK: - DLL Override Resolver

    func testManagedOnlyResolvesToCorrectString() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk),
                (entry: DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "d3d11=n,b;dxgi=n,b")
    }

    func testBottleCustomOverridesManaged() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "dxgi", mode: .builtin)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "dxgi=b")
    }

    func testProgramCustomOverridesAll() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [],
            programCustom: [
                DLLOverrideEntry(dllName: "dxgi", mode: .disabled)
            ]
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "dxgi=")
    }

    func testEmptyResolverProducesEmptyString() {
        let resolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "")
    }

    func testMixedSourcesCompose() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "vcrun", mode: .native)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "dxgi=n,b;vcrun=n")
    }

    // MARK: - DLL Override Warnings

    func testDXVKWarningWhenManagedOverridden() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "dxgi", mode: .builtin)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.dllName, "dxgi")
        XCTAssertEqual(result.warnings.first?.overriddenSource, .dxvk)
    }

    func testNoWarningWhenNoConflict() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "vcrun", mode: .native)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertTrue(result.warnings.isEmpty)
    }

    // MARK: - DXVK Preset

    func testDXVKPresetReturnsCorrectEntries() {
        let preset = DLLOverrideResolver.dxvkPreset
        let names = Set(preset.map(\.dllName))
        XCTAssertEqual(names, Set(["dxgi", "d3d9", "d3d10core", "d3d11"]))
        for entry in preset {
            XCTAssertEqual(entry.mode, .nativeThenBuiltin)
        }
    }
}
