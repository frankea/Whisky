//
//  DLLOverrideRegistryTests.swift
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

final class DLLOverrideRegistryTests: XCTestCase {
    // MARK: - Scope keys

    func testBottleScopeUsesPrefixDefaultKey() {
        XCTAssertEqual(
            Wine.DLLOverrideScope.bottle.registryKey,
            #"HKCU\Software\Wine\DllOverrides"#
        )
    }

    func testProgramScopeIsKeyedOnTheExecutable() {
        XCTAssertEqual(
            Wine.DLLOverrideScope.program("steam.exe").registryKey,
            #"HKCU\Software\Wine\AppDefaults\steam.exe\DllOverrides"#
        )
    }

    /// Two executables must land in different keys, which is the whole point:
    /// an environment variable could not separate a launcher from the games it
    /// spawns.
    func testProgramScopesDoNotCollide() {
        XCTAssertNotEqual(
            Wine.DLLOverrideScope.program("steam.exe").registryKey,
            Wine.DLLOverrideScope.program("steamwebhelper.exe").registryKey
        )
    }

    // MARK: - Parsing

    func testParsesDXVKPreset() {
        let parsed = Wine.parseDLLOverrides("d3d10core=n,b;d3d11=n,b;d3d9=n,b;dxgi=n,b")
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed["d3d11"], "n,b")
        XCTAssertEqual(parsed["dxgi"], "n,b")
    }

    func testParsesBuiltinOnlyModes() {
        let parsed = Wine.parseDLLOverrides("dxgi=b;winemetal=b")
        XCTAssertEqual(parsed["dxgi"], "b")
        XCTAssertEqual(parsed["winemetal"], "b")
    }

    /// `dll=` with no value is how a DLL is disabled, in both the variable and
    /// the registry, so it has to survive the round trip rather than be dropped.
    func testKeepsDisabledOverrides() {
        let parsed = Wine.parseDLLOverrides("mscoree=;mshtml=")
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed["mscoree"], "")
    }

    func testEmptyStringYieldsNoOverrides() {
        XCTAssertTrue(Wine.parseDLLOverrides("").isEmpty)
    }

    func testIgnoresEmptyClausesAndWhitespace() {
        let parsed = Wine.parseDLLOverrides(" d3d11=n,b ;; dxgi=b ;")
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed["d3d11"], "n,b")
        XCTAssertEqual(parsed["dxgi"], "b")
    }

    func testLastClauseWinsForARepeatedDLL() {
        let parsed = Wine.parseDLLOverrides("d3d11=n,b;d3d11=b")
        XCTAssertEqual(parsed["d3d11"], "b")
    }

    // MARK: - Launcher helpers

    /// The reason this exists: steam draws its whole client in the webhelper,
    /// and AppDefaults is per executable with no inheritance, so an override on
    /// steam.exe alone leaves the window blank.
    func testSteamCarriesItsHelpersAlong() {
        let helpers = Wine.helperExecutables(for: URL(filePath: "/B/Steam/steam.exe"))
        XCTAssertTrue(helpers.contains("steamwebhelper.exe"))
    }

    func testAGameIsNotALauncherAndCarriesNothing() {
        let url = URL(filePath: "/B/Steam/steamapps/common/Some Game/game.exe")
        XCTAssertTrue(Wine.helperExecutables(for: url).isEmpty)
    }

    func testUnknownExecutableCarriesNothing() {
        XCTAssertTrue(Wine.helperExecutables(for: URL(filePath: "/B/thing.exe")).isEmpty)
    }

    /// A helper must never be listed as its own helper, or a launch would write
    /// the same scope twice.
    func testNoLauncherListsItself() {
        for launcher in LauncherType.allCases {
            XCTAssertFalse(
                launcher.helperExecutables.contains { $0.lowercased().contains("steam.exe") },
                "\(launcher) lists a launcher executable as a helper"
            )
        }
    }

    // MARK: - Registry document

    func testDocumentWritesEachKeyWithoutDeletingIt() {
        let doc = Wine.registryDocument(for: [
            (key: #"HKCU\Software\Wine\DllOverrides"#, overrides: ["d3d11": "n,b"])
        ])
        XCTAssertTrue(doc.hasPrefix("Windows Registry Editor Version 5.00"))
        // Deleting the key also took every value winetricks or winecfg wrote.
        XCTAssertFalse(doc.contains("[-"))
        XCTAssertTrue(doc.contains(#"[HKCU\Software\Wine\DllOverrides]"#))
        XCTAssertTrue(doc.contains(#""d3d11"="n,b""#))
        // The managed names it does not set are taken back one by one.
        XCTAssertTrue(doc.contains(#""dxgi"=-"#))
        XCTAssertFalse(doc.contains(#""d3d11"=-"#))
    }

    /// An empty scope still takes back what Whisky wrote, since clearing a
    /// backend has to remove what the previous one wrote, and winetricks'
    /// starred spelling of the translation layers.
    func testEmptyScopeRemovesOnlyManagedNames() {
        let doc = Wine.registryDocument(for: [(key: #"HKCU\X"#, overrides: [:])])
        for dll in Wine.managedDLLNames.union(Wine.starredBackendDLLNames) {
            XCTAssertTrue(doc.contains("\"\(dll)\"=-"), dll)
        }
        XCTAssertFalse(doc.contains("[-"))
        XCTAssertFalse(doc.contains(#""*nvapi64"=-"#), "only translation layers are starred")
        XCTAssertEqual(
            doc.components(separatedBy: "\r\n").filter { $0.hasPrefix("\"") }.count,
            Wine.managedDLLNames.count + Wine.starredBackendDLLNames.count
        )
    }

    func testManagedNamesCoverEveryPresetAndTheNVIDIABridges() {
        for payload in [true, false] {
            let presets = DLLOverrideResolver.dxvkPreset(builtinD3D12IsD3DMetal: payload)
                + DLLOverrideResolver.dxmtPreset(builtinD3D12IsD3DMetal: payload)
            for entry in presets {
                XCTAssertTrue(Wine.managedDLLNames.contains(entry.dllName), entry.dllName)
            }
        }
        for dll in ["nvapi", "nvapi64", "nvngx"] {
            XCTAssertTrue(Wine.managedDLLNames.contains(dll), dll)
        }
        // Names only other tools write must never be swept up.
        for dll in ["d3dx9_43", "mscoree", "winemenubuilder", "xaudio2_7", "msvcp140"] {
            XCTAssertFalse(Wine.managedDLLNames.contains(dll), dll)
        }
    }

    func testAllScopesLandInOneDocument() {
        let doc = Wine.registryDocument(for: [
            (key: #"HKCU\A"#, overrides: ["d3d11": "n,b"]),
            (key: #"HKCU\B"#, overrides: ["dxgi": "b"])
        ])
        XCTAssertTrue(doc.contains(#"[HKCU\A]"#))
        XCTAssertTrue(doc.contains(#"[HKCU\B]"#))
        XCTAssertTrue(doc.contains(#""dxgi"="b""#))
    }

    func testValuesAreOrderedDeterministically() {
        let doc = Wine.registryDocument(for: [
            (key: #"HKCU\A"#, overrides: ["dxgi": "b", "d3d11": "n,b", "d3d9": "n,b"])
        ])
        guard let d3d11 = doc.range(of: #""d3d11""#)?.lowerBound,
              let d3d9 = doc.range(of: #""d3d9""#)?.lowerBound,
              let dxgi = doc.range(of: #""dxgi""#)?.lowerBound
        else { return XCTFail("document is missing one of the overrides") }
        XCTAssertLessThan(d3d11, d3d9)
        XCTAssertLessThan(d3d9, dxgi)
    }

    func testDocumentUsesCRLF() {
        let doc = Wine.registryDocument(for: [(key: #"HKCU\A"#, overrides: ["d3d11": "n,b"])])
        XCTAssertTrue(doc.contains("\r\n"))
    }

    // MARK: - Encoding

    func testWrittenDocumentStartsWithAUTF16LEBOM() throws {
        // Wine detects a Unicode .reg by its BOM alone. Without one the file parses
        // as ANSI, matches no header, and the import silently does nothing.
        let doc = Wine.registryDocument(for: [(key: #"HKCU\A"#, overrides: ["d3d11": "n,b"])])
        let url = FileManager.default.temporaryDirectory.appending(path: "bom-\(UUID().uuidString).reg")
        try ("\u{FEFF}" + doc).write(to: url, atomically: true, encoding: .utf16LittleEndian)
        defer { try? FileManager.default.removeItem(at: url) }

        let head = try Data(contentsOf: url).prefix(2)
        XCTAssertEqual(Array(head), [0xFF, 0xFE], "expected a little-endian BOM")
    }

    func testWrittenDocumentRoundTripsThroughAUTF16Reader() throws {
        let doc = Wine.registryDocument(for: [(key: #"HKCU\A"#, overrides: ["d3d11": "n,b"])])
        let url = FileManager.default.temporaryDirectory.appending(path: "rt-\(UUID().uuidString).reg")
        try ("\u{FEFF}" + doc).write(to: url, atomically: true, encoding: .utf16LittleEndian)
        defer { try? FileManager.default.removeItem(at: url) }

        // Reading without naming an encoding is what a BOM is for.
        let read = try String(contentsOf: url)
        XCTAssertTrue(read.hasPrefix("\u{FEFF}Windows Registry Editor Version 5.00"))
        XCTAssertTrue(read.contains(#""d3d11"="n,b""#))
    }

    // MARK: - Rendering safety

    func testAcceptsRealDLLNamesAndModes() {
        for dll in ["d3d11", "d3d10core", "dxgi", "nvapi64", "api-ms-win-crt-runtime-l1-1-0", "d3dx9_43"] {
            XCTAssertTrue(Wine.isRenderable(dll: dll, mode: "native,builtin"), dll)
        }
        for mode in ["native", "builtin", "native,builtin", "builtin,native", ""] {
            XCTAssertTrue(Wine.isRenderable(dll: "d3d11", mode: mode), mode)
        }
    }

    func testRejectsNamesThatWouldBreakOutOfTheValue() {
        // A quote or backslash terminates the value early and corrupts every
        // later scope in the same document.
        for dll in [#"d3d11""#, #"d3d11\"#, "d3d11]\n[HKCU\\Evil", "", "d3d 11", "d3d11;dxgi"] {
            XCTAssertFalse(Wine.isRenderable(dll: dll, mode: "native"), dll.debugDescription)
        }
        for mode in [#"native""#, #"n\b"#, "native]"] {
            XCTAssertFalse(Wine.isRenderable(dll: "d3d11", mode: mode), mode.debugDescription)
        }
    }

    func testOneBadOverrideDoesNotTakeTheDocumentDown() {
        let doc = Wine.registryDocument(for: [
            (key: #"HKCU\A"#, overrides: [#"bad"name"#: "native", "d3d11": "native,builtin"])
        ])
        XCTAssertTrue(doc.contains(#""d3d11"="native,builtin""#), "the good override must survive")
        XCTAssertFalse(doc.contains("bad"), "the unrenderable one must be dropped")
        // Exactly one value line, so nothing was left half-written.
        let values = doc.components(separatedBy: "\r\n").filter { $0.hasPrefix("\"") && !$0.hasSuffix("=-") }
        XCTAssertEqual(values.count, 1)
    }

    func testScopeWhoseOverridesAreAllUnrenderableIsStillPruned() {
        let doc = Wine.registryDocument(for: [(key: #"HKCU\A"#, overrides: [#"bad"name"#: "native"])])
        XCTAssertTrue(doc.contains(#""dxgi"=-"#), "the prune must still be emitted")
        XCTAssertFalse(doc.contains("bad"))
    }
}
