//
//  RockstarD3DDiagnosticsTests.swift
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
import Testing
@testable import WhiskyKit

/// What the diagnostics report and the bottle settings say about the Rockstar
/// swap: the files it wrote against its record, and why a bottle is not
/// swapped (#382).
@Suite("Rockstar Direct3D swap diagnostics and status")
@MainActor
final class RockstarD3DDiagnosticsTests {
    private let fixture: RockstarD3DFixture
    private let root: URL

    init() throws {
        fixture = try RockstarD3DFixture(prefix: "rockstar_diagnostics")
        root = fixture.root
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func section() -> String {
        DiagnosticExporter.generateRockstarLayoutSection(
            bottle: fixture.bottle, options: ExportOptions(), libraryFolder: fixture.library, store: fixture.store,
            dxvkFolder: fixture.dxvk, payloadDeployed: true, recommendedBackend: .d3dMetal
        )
    }

    @Test("system32's d3d11 after the swap is Wine's own, stripped, for the current engine")
    func wineStrippedClassification() throws {
        try fixture.installRockstar()
        try fixture.startSteam()
        let d3d11 = fixture.system32("d3d11.dll")

        #expect(DiagnosticExporter.classifySystem32DLL(d3d11, dxvkFolder: fixture.dxvk, wineSource: fixture.d3d11Source)
            == .wineStripped)
        guard case .nativeOther = DiagnosticExporter.classifySystem32DLL(d3d11, dxvkFolder: fixture.dxvk) else {
            Issue.record("without Wine's source the copy is just another native DLL")
            return
        }
        let report = section()
        #expect(report.contains("- **system32 d3d11.dll:** Wine's own, marker stripped (current engine)"))
        #expect(report.contains("- **system32 dxgi.dll:** Wine's own, marker stripped (current engine)"))
        #expect(report.contains("- **system32 d3d10core.dll:** DXVK payload"))
        #expect(report.contains("- **Layout now:** swapped ("))
        #expect(report.contains("- **d3d11 source:** GPTK originals (originals/d3d11.dll)"))
    }

    @Test("The record's lines tell each copy apart from what Whisky wrote")
    func recordLinesClassifyCopies() throws {
        try fixture.installRockstar()
        try fixture.startSteam()
        let cef64 = fixture.steamRoot.appending(path: "bin/cef/cef.win64")
        try Data("steam's own".utf8).write(to: cef64.appending(path: "d3d11.dll"))
        try FileManager.default.removeItem(at: fixture.steamRoot.appending(path: "bin/cef/cef.win7x64/d3d11.dll"))
        try fixture.makeDXVK(version: "2")
        try RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll", version: "2")
            .write(to: fixture.steamRoot.appending(path: "d3d11.dll"))

        let lines = DiagnosticExporter.rockstarRecordLines(
            fixture.record, bottle: fixture.bottle, dxvkFolder: fixture.dxvk, runtime: fixture.runtime
        )

        let steam = RockstarD3DFixture.steamKey
        #expect(lines.contains("- **Swap record:** version 1"))
        #expect(lines.contains("- **Swap record engine:** 4.8.3, matches"))
        #expect(lines.contains(", the current file matches"))
        #expect(lines.contains("  - \(steam)/bin/cef/cef.win64/d3d11.dll: changed ("))
        #expect(lines.contains("  - \(steam)/bin/cef/cef.win7x64/d3d11.dll: missing"))
        #expect(lines.contains("  - \(steam)/d3d11.dll: DXVK payload (unrecorded)"))
        #expect(lines.contains("  - \(steam)/d3d10core.dll: Whisky's copy"))
        #expect(!lines.contains("created folder"))
    }

    @Test("A bottle with a record and no Rockstar folder still gets the section")
    func sectionForARecordAlone() throws {
        try RockstarD3DLayoutRecord(engineStamp: "4.8.2", sourceSHA256: "abc", createdFolders: ["Gone/Folder"])
            .save(to: fixture.bottle.url)

        let report = section()

        #expect(report.hasPrefix("### Rockstar Launcher Layout\n\n"))
        #expect(report.contains("- **Swap record engine:** 4.8.2, differs (installed 4.8.3)"))
        #expect(report.contains("- **Swap record system32 d3d11:** not recorded (interrupted swap)"))
        #expect(report.contains("- **Swap record created folder:** Gone/Folder (gone)"))
        // Without Rockstar, the next Steam start takes the swap back whatever the runtime allows.
        #expect(report.contains("- **Layout now:** teardown (Rockstar is not installed)"))
        #expect(!report.contains("\u{2014}"))
    }

    @Test("Layout now names the reason a bottle is not swapped")
    func layoutNowNamesTheReason() throws {
        try fixture.installRockstar()
        fixture.bottle.settings.rockstarWineD3D = false

        let report = section()

        #expect(report.contains("- **Wine Direct3D swap setting:** off"))
        #expect(report.contains("- **Layout now:** degraded (disabledByUser: "))
        #expect(report.contains("- **Layout at the last launch:** no launch this session"))
        #expect(report.contains("- **Swap record:** none"))
    }

    // MARK: - Status

    @Test("The settings row follows the record, the setting and the last launch's layout")
    func status() throws {
        let bottle = fixture.bottle
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: true) == nil)

        try fixture.installRockstar()
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: false) == nil)
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: true) == .pending)

        try fixture.startSteam()
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: true) == .active)
        // After the app restarts, the record alone says active.
        bottle.rockstarD3DLayout = nil
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: true) == .active)

        // A launch that did not decide on the swap says nothing about it.
        bottle.rockstarD3DLayout = .degraded(.gptkForwarders)
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: true) == .active)

        bottle.rockstarD3DLayout = .degraded(.dxvkPlanGames(["Game"]))
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: true) == .notApplied(.dxvkPlanGames(["Game"])))

        bottle.settings.rockstarWineD3D = false
        #expect(bottle.rockstarWineD3DStatus(payloadDeployed: true) == .off)
    }
}
