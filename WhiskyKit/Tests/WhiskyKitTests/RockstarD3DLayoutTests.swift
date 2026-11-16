//
//  RockstarD3DLayoutTests.swift
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

/// Which Direct3D Rockstar's `Launcher.exe` can be given, decided by what the
/// runtime's `d3d11.dll` and `dxgi.dll` slots hold, and the diagnostics
/// section that reports it (#382).
@Suite("Rockstar Direct3D layout")
@MainActor
final class RockstarD3DLayoutTests {
    private let root: URL
    private let library: URL
    private let store: URL
    private let dxvk: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "rockstar_layout_\(UUID().uuidString)")
        library = root.appending(path: "Libraries")
        store = root.appending(path: "D3DMetal")
        dxvk = root.appending(path: "DXVK")
        for name in ["d3d11.dll", "dxgi.dll"] {
            try write("apple \(name)", to: storePE.appending(path: name))
        }
        // The Wine originals deploy backed up, which runtime(...) restores.
        try write("wine d3d11", to: store.appending(path: "originals/d3d11.dll"))
        try write("wine dxgi", to: store.appending(path: "originals/dxgi.dll"))
        try write("dxvk d3d11", to: dxvk.appending(path: "x64/d3d11.dll"))
        try write("dxvk d3d10core", to: dxvk.appending(path: "x64/d3d10core.dll"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private var storePE: URL {
        store.appending(path: "lib/wine/x86_64-windows")
    }

    private var runtimePE: URL {
        library.appending(path: "Wine/lib/wine/x86_64-windows")
    }

    private func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// The runtime's slots: Apple's forwarder or Wine's own DLL in each.
    private func runtime(d3d11Forwarder: Bool, dxgiForwarder: Bool) throws {
        try write(d3d11Forwarder ? "apple d3d11.dll" : "wine d3d11", to: runtimePE.appending(path: "d3d11.dll"))
        try write(dxgiForwarder ? "apple dxgi.dll" : "wine dxgi", to: runtimePE.appending(path: "dxgi.dll"))
    }

    // MARK: - Resolution

    @Test("Wine's own builtins only while neither slot leads to D3DMetal", arguments: [
        (false, false, RockstarD3DLayout.builtin),
        (true, false, .degraded(.gptkForwarders)),
        (false, true, .degraded(.gptkForwarders)),
        (true, true, .degraded(.gptkForwarders))
    ])
    func layoutFollowsTheSlots(_ d3d11: Bool, _ dxgi: Bool, _ expected: RockstarD3DLayout) throws {
        #expect(RockstarD3DLayout.resolve(d3d11IsForwarder: d3d11, dxgiIsForwarder: dxgi) == expected)

        try runtime(d3d11Forwarder: d3d11, dxgiForwarder: dxgi)
        let slots = RockstarD3DLayout.forwarders(libraryFolder: library, store: store)
        #expect(slots.d3d11 == d3d11)
        #expect(slots.dxgi == dxgi)
        #expect(RockstarD3DLayout.resolve(payloadDeployed: true, libraryFolder: library, store: store) == expected)
    }

    @Test("Without the payload deployed the slots are not read: the layout is builtin")
    func noPayloadIsBuiltin() throws {
        try runtime(d3d11Forwarder: true, dxgiForwarder: true)

        #expect(RockstarD3DLayout.resolve(payloadDeployed: false, libraryFolder: library, store: store) == .builtin)
    }

    @Test("The DXGI driver version shim in front of Apple's dxgi counts as D3DMetal")
    func dxgiShimCounts() throws {
        try runtime(d3d11Forwarder: false, dxgiForwarder: false)
        try write("dxgi shim", to: library.appending(path: "Wine/lib/gptk-video/dxgishim.dll"))
        try write("dxgi shim", to: runtimePE.appending(path: "dxgi.dll"))

        #expect(RockstarD3DLayout.forwarders(libraryFolder: library, store: store).dxgi)
        #expect(RockstarD3DLayout.resolve(payloadDeployed: true, libraryFolder: library, store: store)
            == .degraded(.gptkForwarders))
    }

    @Test("Missing slots and a missing store are no forwarders, and no Wine originals either")
    func missingFilesAreNotForwarders() {
        let nothing = root.appending(path: "nothing")
        let noStore = root.appending(path: "no store")
        let slots = RockstarD3DLayout.forwarders(libraryFolder: nothing, store: noStore)
        #expect(!slots.d3d11)
        #expect(!slots.dxgi)
        let originals = RockstarD3DLayout.wineOriginals(libraryFolder: nothing, store: noStore)
        #expect(!originals.d3d11)
        #expect(!originals.dxgi)
        // With the payload deployed, nothing to vouch for the slots is D3DMetal.
        #expect(RockstarD3DLayout.resolve(payloadDeployed: true, libraryFolder: nothing, store: noStore)
            == .degraded(.gptkForwarders))
    }

    @Test("A payload copied in by hand degrades, though it matches no forwarder in the store")
    func handPlacedPayloadDegrades() throws {
        try write("hand-placed apple d3d11", to: runtimePE.appending(path: "d3d11.dll"))
        try write("hand-placed apple dxgi", to: runtimePE.appending(path: "dxgi.dll"))

        for store in [store, root.appending(path: "no store")] {
            let slots = RockstarD3DLayout.forwarders(libraryFolder: library, store: store)
            #expect(!slots.d3d11 && !slots.dxgi)
            #expect(RockstarD3DLayout.resolve(payloadDeployed: true, libraryFolder: library, store: store)
                == .degraded(.gptkForwarders))
        }
    }

    @Test("One slot that is not the stored Wine original is enough to degrade")
    func oneUnknownSlotDegrades() throws {
        try runtime(d3d11Forwarder: false, dxgiForwarder: false)
        try write("another engine's dxgi", to: runtimePE.appending(path: "dxgi.dll"))

        let originals = RockstarD3DLayout.wineOriginals(libraryFolder: library, store: store)
        #expect(originals.d3d11)
        #expect(!originals.dxgi)
        #expect(RockstarD3DLayout.resolve(payloadDeployed: true, libraryFolder: library, store: store)
            == .degraded(.gptkForwarders))
    }

    // MARK: - Diagnostics

    private func makeBottle(rockstar: Bool) throws -> Bottle {
        let bottleURL = root.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        if rockstar {
            try FileManager.default.createDirectory(
                at: bottleURL.appending(path: "drive_c/Program Files/Rockstar Games/Launcher"),
                withIntermediateDirectories: true
            )
        }
        return Bottle(bottleUrl: bottleURL)
    }

    private func section(_ bottle: Bottle, payloadDeployed: Bool = true) -> String {
        DiagnosticExporter.generateRockstarLayoutSection(
            bottle: bottle, options: ExportOptions(), libraryFolder: library, store: store,
            dxvkFolder: dxvk, payloadDeployed: payloadDeployed
        )
    }

    @Test("A bottle without Rockstar gets no layout section")
    func noSectionWithoutRockstar() throws {
        let bottle = try makeBottle(rockstar: false)

        #expect(section(bottle).isEmpty)
    }

    @Test("The section reports the layout, the slots, system32 and the AppDefaults entries")
    func sectionClassifiesTheBottle() throws {
        try runtime(d3d11Forwarder: true, dxgiForwarder: false)
        let bottle = try makeBottle(rockstar: true)
        let system32 = bottle.url.appending(path: "drive_c/windows/system32")
        try write("dxvk d3d11", to: system32.appending(path: "d3d11.dll"))
        var placeholder = Data(count: 0x40)
        placeholder.append(Data("Wine builtin DLL".utf8))
        try write(placeholder, to: system32.appending(path: "dxgi.dll"))
        let userReg = #"""
        WINE REGISTRY Version 2

        [Software\\Wine\\AppDefaults\\Launcher.exe\\Direct3D] 1731628800
        "renderer"="gl"

        [Software\\Wine\\AppDefaults\\Launcher.exe\\DllOverrides] 1731628800
        "d3d11"="b"
        "dxgi"="b"

        """#
        try userReg.write(to: bottle.url.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        bottle.settings.gameConfigEnvironments = [GameConfigEnvironment(
            entryId: "test", title: "Test", executables: [], variables: ["WINE_D3D_CONFIG": "renderer=vulkan"]
        )]

        let report = section(bottle)

        #expect(report.hasPrefix("### Rockstar Launcher Layout\n\n"))
        #expect(report.contains("- **Layout:** degraded (gptkForwarders"))
        #expect(report.contains("- **Runtime d3d11.dll is a GPTK forwarder:** yes"))
        #expect(report.contains("- **Runtime dxgi.dll is a GPTK forwarder:** no"))
        #expect(report.contains("- **GPTK payload deployed:** yes"))
        #expect(report.contains("- **Runtime d3d11.dll is the stored Wine original:** no"))
        #expect(report.contains("- **Runtime dxgi.dll is the stored Wine original:** yes"))
        #expect(report.contains("- **system32 d3d11.dll:** DXVK payload"))
        #expect(report.contains("- **system32 dxgi.dll:** builtin placeholder"))
        #expect(report.contains("- **system32 d3d10core.dll:** missing"))
        #expect(report.contains(#"- **AppDefaults Launcher.exe\DllOverrides:** d3d11="b", dxgi="b""#))
        #expect(report.contains(#"- **AppDefaults Launcher.exe\Direct3D:** renderer="gl""#))
        #expect(report.contains(#"- **AppDefaults SocialClubHelper.exe\DllOverrides:** none"#))
        #expect(report.contains("- **WINEDLLOVERRIDES set for Launcher.exe:** no"))
        #expect(report.contains("- **WINE_D3D_CONFIG set for Launcher.exe:** yes (game configuration)"))
    }

    @Test("The section names the Launcher.exe program settings that set either variable")
    func sectionReadsTheProgramsEnvironment() throws {
        let bottle = try makeBottle(rockstar: true)
        let launcher = bottle.url.appending(path: "drive_c/Program Files/Rockstar Games/Launcher/Launcher.exe")
        let settingsURL = Program.settingsLocations(
            for: launcher, bottleURL: bottle.url, legacyName: launcher.lastPathComponent
        ).identity
        var settings = ProgramSettings()
        settings.environment = ["WINE_D3D_CONFIG": "renderer=vulkan", "WINEDLLOVERRIDES": "d3d11=n"]
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try settings.encode(to: settingsURL)

        let report = section(bottle)

        #expect(report.contains("- **WINEDLLOVERRIDES set for Launcher.exe:** yes (program settings)"))
        #expect(report.contains("- **WINE_D3D_CONFIG set for Launcher.exe:** yes (program settings)"))
    }

    @Test("Without the payload the section reports the builtin layout")
    func sectionWithoutPayload() throws {
        try runtime(d3d11Forwarder: false, dxgiForwarder: false)
        let bottle = try makeBottle(rockstar: true)

        #expect(section(bottle, payloadDeployed: false).contains("- **Layout:** builtin"))
    }

    @Test("A system32 file that is neither Wine's nor DXVK's is named by its digest")
    func nativeOtherIsNamedByDigest() throws {
        let file = root.appending(path: "d3d11.dll")
        try write("someone else's d3d11", to: file)

        let kind = DiagnosticExporter.classifySystem32DLL(file, dxvkFolder: dxvk)

        // The first eight hex digits of the file's SHA-256.
        guard case let .nativeOther(digest) = kind else {
            Issue.record("expected a native file, got \(kind)")
            return
        }
        let isHex = digest.allSatisfy(\.isHexDigit)
        #expect(digest.count == 8)
        #expect(isHex)
        #expect(DiagnosticExporter.classifySystem32DLL(root.appending(path: "absent.dll"), dxvkFolder: dxvk)
            == .missing)
    }
}
