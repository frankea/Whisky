//
//  WineDXMTTests.swift
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

final class WineDXMTTests: XCTestCase {
    private var tempDir: URL!
    private var payloadRoot: URL!
    private var wineLibRoot: URL!
    private var prefixRoot: URL!

    private let trio = ["d3d11.dll", "dxgi.dll", "d3d10core.dll"]

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        payloadRoot = tempDir.appending(path: "DXMT")
        wineLibRoot = tempDir.appending(path: "Wine/lib/wine")
        prefixRoot = tempDir.appending(path: "bottle")

        // DXMT payload as shipped in the runtime: trio + winemetal + NVIDIA
        // extras in x64; trio + winemetal in x32.
        for (arch, extras) in [("x64", ["nvapi64.dll", "nvngx.dll"]), ("x32", [])] {
            let dir = payloadRoot.appending(path: arch)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in trio + ["winemetal.dll"] + extras {
                try Data("dxmt-\(arch)-\(name)".utf8).write(to: dir.appending(path: name))
            }
        }

        // Wine builtin trees: x86_64 carries the stale Gcenx winemetal stub.
        let x64Builtin = wineLibRoot.appending(path: "x86_64-windows")
        try FileManager.default.createDirectory(at: x64Builtin, withIntermediateDirectories: true)
        try Data("gcenx-stub".utf8).write(to: x64Builtin.appending(path: "winemetal.dll"))

        // Prefix with fakedlls in system32 and an existing syswow64 tree.
        let system32 = prefixRoot.appending(path: "drive_c/windows/system32")
        let syswow64 = prefixRoot.appending(path: "drive_c/windows/syswow64")
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syswow64, withIntermediateDirectories: true)
        for name in trio {
            try Data("fakedll-\(name)".utf8).write(to: system32.appending(path: name))
        }
        // syswow64 left WITHOUT the trio to exercise copy-if-missing.
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testTrioReplacedInSystem32AndCopiedIntoSyswow64() throws {
        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        for name in trio {
            let system32DLL = prefixRoot.appending(path: "drive_c/windows/system32").appending(path: name)
            XCTAssertEqual(try contents(system32DLL), "dxmt-x64-\(name)", "\(name) should be replaced")
            // syswow64 had no pre-existing DLLs: a skipped copy here would mean
            // 32-bit programs silently fall back to the builtin path.
            let syswow64DLL = prefixRoot.appending(path: "drive_c/windows/syswow64").appending(path: name)
            XCTAssertEqual(try contents(syswow64DLL), "dxmt-x32-\(name)", "\(name) should be copied even if absent")
        }
    }

    func testQuarantinedPayloadDLLsNeverEnterThePrefix() throws {
        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        for dir in ["system32", "syswow64"] {
            for name in ["winemetal.dll", "nvapi64.dll", "nvngx.dll"] {
                let url = prefixRoot.appending(path: "drive_c/windows").appending(path: dir).appending(path: name)
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: url.path),
                    "\(name) must not be installed into \(dir): winemetal only works as a builtin"
                )
            }
        }
    }

    func testWinemetalBuiltinReplacedWhenContentDiffers() throws {
        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        let builtin = wineLibRoot.appending(path: "x86_64-windows").appending(path: "winemetal.dll")
        XCTAssertEqual(
            try contents(builtin), "dxmt-x64-winemetal.dll",
            "The stale Wine-build winemetal stub must be replaced with DXMT's matching PE"
        )
    }

    func testWinemetalBuiltinLeftAloneWhenIdentical() throws {
        // Pre-place DXMT's exact winemetal — a second enable must not rewrite it.
        let builtin = wineLibRoot.appending(path: "x86_64-windows").appending(path: "winemetal.dll")
        try Data("dxmt-x64-winemetal.dll".utf8).write(to: builtin)
        let before = try FileManager.default.attributesOfItem(atPath: builtin.path)[.modificationDate] as? Date

        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        let after = try FileManager.default.attributesOfItem(atPath: builtin.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after, "Identical winemetal must not be rewritten (idempotence)")
        XCTAssertEqual(try contents(builtin), "dxmt-x64-winemetal.dll")
    }

    func testI386BuiltinTreePopulatedWhenPresent() throws {
        let i386 = wineLibRoot.appending(path: "i386-windows")
        try FileManager.default.createDirectory(at: i386, withIntermediateDirectories: true)
        try Data("gcenx-stub-32".utf8).write(to: i386.appending(path: "winemetal.dll"))

        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        XCTAssertEqual(try contents(i386.appending(path: "winemetal.dll")), "dxmt-x32-winemetal.dll")
    }

    func testI386BuiltinTreeSkippedWhenAbsent() throws {
        // No i386-windows directory in this Wine layout: enable must not create
        // it or fail.
        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        let i386 = wineLibRoot.appending(path: "i386-windows")
        XCTAssertFalse(FileManager.default.fileExists(atPath: i386.path))
    }

    func testSyswow64SkippedWhenAbsent() throws {
        try FileManager.default.removeItem(at: prefixRoot.appending(path: "drive_c/windows/syswow64"))

        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        let syswow64 = prefixRoot.appending(path: "drive_c/windows/syswow64")
        XCTAssertFalse(FileManager.default.fileExists(atPath: syswow64.path))
    }

    func testMissingPayloadThrowsActionableError() throws {
        try FileManager.default.removeItem(at: payloadRoot)

        XCTAssertThrowsError(
            try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)
        ) { error in
            XCTAssertEqual(error as? Wine.DXMTError, .payloadMissing)
            // Surfaces through the launch-failure toast via localizedDescription.
            XCTAssertFalse((error as? Wine.DXMTError)?.errorDescription?.isEmpty ?? true)
        }
    }

    func testSecondEnableIsIdempotent() throws {
        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)
        try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)

        let system32DLL = prefixRoot.appending(path: "drive_c/windows/system32").appending(path: "d3d11.dll")
        XCTAssertEqual(try contents(system32DLL), "dxmt-x64-d3d11.dll")
    }

    func testMissingWinemetalInPayloadThrowsAndPreservesState() throws {
        // A damaged runtime: the x64 trio is present but winemetal.dll is gone.
        // The guard must catch this BEFORE any copy, so the existing builtin
        // winemetal is preserved (its loss would degrade even non-DXMT launches)
        // and the prefix trio is left untouched.
        try FileManager.default.removeItem(at: payloadRoot.appending(path: "x64/winemetal.dll"))
        let builtin = wineLibRoot.appending(path: "x86_64-windows").appending(path: "winemetal.dll")
        let system32D3D11 = prefixRoot.appending(path: "drive_c/windows/system32").appending(path: "d3d11.dll")

        XCTAssertThrowsError(
            try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)
        ) { error in
            XCTAssertEqual(error as? Wine.DXMTError, .payloadMissing)
        }
        XCTAssertEqual(try contents(builtin), "gcenx-stub", "Existing builtin winemetal must be preserved")
        XCTAssertEqual(try contents(system32D3D11), "fakedll-d3d11.dll", "Prefix trio must not be half-deployed")
    }

    func testIncompleteX32PayloadThrowsWhenSyswow64Present() throws {
        // syswow64 exists (32-bit deployment will be attempted), but the x32 trio
        // is incomplete. The guard must throw before touching the prefix.
        try FileManager.default.removeItem(at: payloadRoot.appending(path: "x32/dxgi.dll"))
        let system32D3D11 = prefixRoot.appending(path: "drive_c/windows/system32").appending(path: "d3d11.dll")

        XCTAssertThrowsError(
            try Wine.enableDXMT(payloadRoot: payloadRoot, wineLibRoot: wineLibRoot, prefixRoot: prefixRoot)
        ) { error in
            XCTAssertEqual(error as? Wine.DXMTError, .payloadMissing)
        }
        XCTAssertEqual(try contents(system32D3D11), "fakedll-d3d11.dll", "Prefix must not be touched")
    }

    func testInstallFilePreservesDestinationWhenSourceMissing() throws {
        // installFile must not delete an existing destination until the new file
        // is safely in hand — a failed copy can never leave the destination gone.
        let dest = tempDir.appending(path: "existing.dll")
        try Data("original".utf8).write(to: dest)
        let missingSource = tempDir.appending(path: "does-not-exist.dll")

        XCTAssertThrowsError(try FileManager.default.installFile(at: dest, from: missingSource))
        XCTAssertEqual(try contents(dest), "original", "Destination must survive a failed copy")
    }
}
