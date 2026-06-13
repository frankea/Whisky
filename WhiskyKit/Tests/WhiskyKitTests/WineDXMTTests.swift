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
    private var prefixRoot: URL!

    private let trio = ["d3d11.dll", "dxgi.dll", "d3d10core.dll"]
    /// Everything DXMT deploys into the prefix: the native trio + the
    /// builtin-marked `winemetal.dll` redirect.
    private var deployed: [String] {
        trio + ["winemetal.dll"]
    }

    /// A markerless (native) PE stub whose 16-byte window at 0x40 is *not* the
    /// builtin signature — `Wine.isNativePE` must classify it as native. The
    /// trailing zero padding guarantees a full 16 bytes past 0x40 (a real native
    /// PE always has a DOS stub there), while the embedded tag keeps the content
    /// unique so deploy assertions can match source to destination.
    private func nativeFake(_ tag: String) -> Data {
        Data(count: 0x40) + Data(tag.utf8) + Data(count: 16)
    }

    /// A PE stub carrying winebuild's "Wine builtin DLL" signature at 0x40.
    private func builtinFake(_ tag: String) -> Data {
        Data(count: 0x40) + Data("Wine builtin DLL".utf8) + Data(tag.utf8)
    }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        payloadRoot = tempDir.appending(path: "DXMT")
        prefixRoot = tempDir.appending(path: "bottle")

        // DXMT payload as shipped by the native-variant runtime: native trio +
        // builtin-marked winemetal in both arches; NVIDIA extras in x64.
        for (arch, extras) in [("x64", ["nvapi64.dll", "nvngx.dll"]), ("x32", [])] {
            let dir = payloadRoot.appending(path: arch)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in trio + extras {
                try nativeFake("dxmt-\(arch)-\(name)").write(to: dir.appending(path: name))
            }
            try builtinFake("dxmt-\(arch)-winemetal.dll").write(to: dir.appending(path: "winemetal.dll"))
        }

        // Prefix with fakedlls in system32 and an existing (empty) syswow64.
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

    private func system32(_ name: String) -> URL {
        prefixRoot.appending(path: "drive_c/windows/system32").appending(path: name)
    }

    private func syswow64(_ name: String) -> URL {
        prefixRoot.appending(path: "drive_c/windows/syswow64").appending(path: name)
    }

    private func data(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func testTrioAndWinemetalDeployedNativeIntoBothArches() throws {
        try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)

        for name in deployed {
            // 64-bit: replaces the fakedll trio / copies winemetal in.
            XCTAssertEqual(
                try data(system32(name)), try data(payloadRoot.appending(path: "x64").appending(path: name)),
                "\(name) should be deployed from the x64 payload into system32"
            )
            // 32-bit: syswow64 had no pre-existing DLLs — a skipped copy here
            // would leave 32-bit programs falling back to the builtin path.
            XCTAssertEqual(
                try data(syswow64(name)), try data(payloadRoot.appending(path: "x32").appending(path: name)),
                "\(name) should be copied into syswow64 even when absent"
            )
        }
    }

    func testNvidiaExtrasNeverEnterThePrefix() throws {
        try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)

        // winemetal IS deployed (it backs the trio's import); nvapi64/nvngx are
        // deliberately quarantined — DXMT's NVIDIA spoofing is out of scope.
        for name in ["nvapi64.dll", "nvngx.dll"] {
            XCTAssertFalse(exists(system32(name)), "\(name) must not be installed into system32")
            XCTAssertFalse(exists(syswow64(name)), "\(name) must not be installed into syswow64")
        }
    }

    func testWinemetalIsDeployedIntoThePrefix() throws {
        // The trio imports winemetal.dll by name; the prefix needs the
        // builtin-marked redirect so that import resolves to the lib/wine builtin.
        try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)

        XCTAssertTrue(exists(system32("winemetal.dll")), "winemetal.dll must be present in system32")
        XCTAssertEqual(
            try data(system32("winemetal.dll")),
            try data(payloadRoot.appending(path: "x64").appending(path: "winemetal.dll"))
        )
    }

    func testSyswow64SkippedWhenAbsent() throws {
        try FileManager.default.removeItem(at: prefixRoot.appending(path: "drive_c/windows/syswow64"))

        try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)

        // 64-bit half still deployed; the absent syswow64 must not be recreated.
        XCTAssertEqual(try data(system32("d3d11.dll")), try data(payloadRoot.appending(path: "x64/d3d11.dll")))
        XCTAssertFalse(exists(prefixRoot.appending(path: "drive_c/windows/syswow64")))
    }

    func testBuiltinMarkedTrioRejectedAndPrefixUntouched() throws {
        // An older (builtin-variant) runtime: the trio carries the "Wine builtin
        // DLL" marker. Deploying it would be silently ignored by the loader in
        // favor of wined3d, so enable must refuse and leave the prefix untouched
        // rather than launch a bottle that isn't really using DXMT.
        try builtinFake("builtin-x64-d3d11.dll")
            .write(to: payloadRoot.appending(path: "x64/d3d11.dll"))

        XCTAssertThrowsError(
            try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)
        ) { error in
            XCTAssertEqual(error as? Wine.DXMTError, .payloadMissing)
        }
        XCTAssertEqual(try data(system32("d3d11.dll")), Data("fakedll-d3d11.dll".utf8), "Prefix must not be touched")
    }

    func testMissingPayloadThrowsActionableErrorAndPreservesPrefix() throws {
        try FileManager.default.removeItem(at: payloadRoot.appending(path: "x64/dxgi.dll"))

        XCTAssertThrowsError(
            try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)
        ) { error in
            XCTAssertEqual(error as? Wine.DXMTError, .payloadMissing)
            // Surfaces through the launch-failure toast via localizedDescription.
            XCTAssertFalse((error as? Wine.DXMTError)?.errorDescription?.isEmpty ?? true)
        }
        XCTAssertEqual(try data(system32("d3d11.dll")), Data("fakedll-d3d11.dll".utf8), "Prefix must not be touched")
    }

    func testIncompleteX32PayloadThrowsWhenSyswow64Present() throws {
        // syswow64 exists (32-bit deploy will be attempted) but the x32 payload
        // is incomplete. The guard must throw before touching the prefix.
        try FileManager.default.removeItem(at: payloadRoot.appending(path: "x32/dxgi.dll"))

        XCTAssertThrowsError(
            try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)
        ) { error in
            XCTAssertEqual(error as? Wine.DXMTError, .payloadMissing)
        }
        XCTAssertEqual(try data(system32("d3d11.dll")), Data("fakedll-d3d11.dll".utf8), "Prefix must not be touched")
    }

    func testSecondEnableIsIdempotent() throws {
        try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)
        try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)

        XCTAssertEqual(try data(system32("d3d11.dll")), try data(payloadRoot.appending(path: "x64/d3d11.dll")))
    }

    func testIsNativePEDistinguishesBuiltinFromNative() throws {
        let native = tempDir.appending(path: "native.dll")
        let builtin = tempDir.appending(path: "builtin.dll")
        try nativeFake("native").write(to: native)
        try builtinFake("builtin").write(to: builtin)

        XCTAssertTrue(try Wine.isNativePE(native))
        XCTAssertFalse(try Wine.isNativePE(builtin))
    }

    func testShortFileIsTreatedAsNotNative() throws {
        // A file too short to hold the 16-byte signature at 0x40 (a truncated or
        // corrupt payload) must be classified not-native — fail-closed, so it is
        // never deployed as if it were a working native DLL.
        let short = tempDir.appending(path: "short.dll")
        try Data("MZ".utf8).write(to: short)
        XCTAssertFalse(try Wine.isNativePE(short))
    }

    func testIsDXMTRuntimeNativeReflectsPayloadVariant() throws {
        // Native payload (setUp writes a markerless d3d11) → available.
        XCTAssertTrue(Wine.isDXMTRuntimeNative(payloadRoot: payloadRoot))

        // Builtin-variant payload (the older runtime) → not available.
        try builtinFake("builtin-d3d11").write(to: payloadRoot.appending(path: "x64/d3d11.dll"))
        XCTAssertFalse(Wine.isDXMTRuntimeNative(payloadRoot: payloadRoot))

        // Absent payload → not available.
        try FileManager.default.removeItem(at: payloadRoot.appending(path: "x64/d3d11.dll"))
        XCTAssertFalse(Wine.isDXMTRuntimeNative(payloadRoot: payloadRoot))
    }

    func testBuiltinMarkedNonD3D11TrioMemberRejected() throws {
        // The guard inspects the whole trio, not just d3d11: a builtin-marked dxgi
        // must also be refused, with the prefix left untouched.
        try builtinFake("builtin-dxgi").write(to: payloadRoot.appending(path: "x64/dxgi.dll"))

        XCTAssertThrowsError(
            try Wine.enableDXMT(payloadRoot: payloadRoot, prefixRoot: prefixRoot)
        ) { error in
            XCTAssertEqual(error as? Wine.DXMTError, .payloadMissing)
        }
        XCTAssertEqual(try data(system32("d3d11.dll")), Data("fakedll-d3d11.dll".utf8), "Prefix must not be touched")
    }

    func testInstallFilePreservesDestinationWhenSourceMissing() throws {
        // installFile must not delete an existing destination until the new file
        // is safely in hand — a failed copy can never leave the destination gone.
        let dest = tempDir.appending(path: "existing.dll")
        try Data("original".utf8).write(to: dest)
        let missingSource = tempDir.appending(path: "does-not-exist.dll")

        XCTAssertThrowsError(try FileManager.default.installFile(at: dest, from: missingSource))
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "original", "Destination must survive failure")
    }
}
