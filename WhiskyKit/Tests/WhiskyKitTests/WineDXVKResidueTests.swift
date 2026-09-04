//
//  WineDXVKResidueTests.swift
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

final class WineDXVKResidueTests: XCTestCase {
    private var tempDir: URL!
    private var prefixRoot: URL!
    private var originalsDXGI: URL!

    /// A markerless (native) PE stub: the 16 bytes at 0x40 are not the
    /// builtin signature, so `Wine.isNativePE` classifies it as native.
    private func nativeFake(_ tag: String) -> Data {
        Data(count: 0x40) + Data(tag.utf8) + Data(count: 16)
    }

    /// A PE stub carrying winebuild's "Wine builtin DLL" signature at 0x40.
    private func builtinFake(_ tag: String) -> Data {
        Data(count: 0x40) + Data("Wine builtin DLL".utf8) + Data(tag.utf8)
    }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        prefixRoot = tempDir.appending(path: "bottle")
        // An originals path that does not exist unless a test creates it.
        originalsDXGI = tempDir.appending(path: "store/originals/dxgi.dll")
        for dir in ["system32", "syswow64"] {
            try FileManager.default.createDirectory(
                at: prefixRoot.appending(path: "drive_c/windows/\(dir)"),
                withIntermediateDirectories: true
            )
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func dxgi(_ dir: String) -> URL {
        prefixRoot.appending(path: "drive_c/windows/\(dir)/dxgi.dll")
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The regression this guards: a DXMT launch leaves its native dxgi in
    /// both system directories, and the next DXVK launch must clear them.
    func testNativeResidueIsRemovedFromBothArches() throws {
        try nativeFake("dxmt-64").write(to: dxgi("system32"))
        try nativeFake("dxmt-32").write(to: dxgi("syswow64"))
        let bystander = prefixRoot.appending(path: "drive_c/windows/system32/d3d11.dll")
        try nativeFake("dxvk-d3d11").write(to: bystander)

        Wine.removeStaleNativeDXGI(prefixRoot: prefixRoot, libraryFolder: noRuntime)

        XCTAssertFalse(exists(dxgi("system32")))
        XCTAssertFalse(exists(dxgi("syswow64")))
        XCTAssertTrue(exists(bystander), "only dxgi.dll may be touched")
    }

    /// Wine's own fake DLL carries the builtin marker and must stay: it is
    /// what redirects the loader to the builtin DXVK pairs with.
    func testBuiltinMarkedDXGIIsKept() throws {
        try builtinFake("wine-fake").write(to: dxgi("system32"))

        Wine.removeStaleNativeDXGI(prefixRoot: prefixRoot, libraryFolder: noRuntime)

        XCTAssertTrue(exists(dxgi("system32")))
    }

    /// A prefix that never saw DXMT has no dxgi.dll of its own; the removal
    /// must be a silent no-op.
    func testMissingDXGIIsANoOp() {
        Wine.removeStaleNativeDXGI(prefixRoot: prefixRoot, libraryFolder: noRuntime)

        XCTAssertFalse(exists(dxgi("system32")))
        XCTAssertFalse(exists(dxgi("syswow64")))
    }

    /// A file too short to hold the marker window is not classified native
    /// (`isNativePE` fails closed), so a truncated stray survives rather than
    /// being mistaken for DXMT residue.
    func testTruncatedFileIsLeftAlone() throws {
        try Data("stub".utf8).write(to: dxgi("system32"))

        Wine.removeStaleNativeDXGI(prefixRoot: prefixRoot, libraryFolder: noRuntime)

        XCTAssertTrue(exists(dxgi("system32")))
    }

    // MARK: - Reconciliation against the GPTK payload

    private func writeOriginals(_ contents: Data) throws {
        try FileManager.default.createDirectory(
            at: originalsDXGI.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: originalsDXGI)
    }

    private func markerWindow(_ url: URL) throws -> Data {
        try Data(contentsOf: url).subdata(in: 0x40 ..< 0x50)
    }

    /// With the payload deployed the builtin is Apple's forwarder, so the
    /// stored original is installed and its builtin marker stripped, leaving a
    /// file the loader takes as a true native PE.
    func testDeployedPayloadInstallsStrippedOriginal() throws {
        try writeOriginals(builtinFake("stored-original"))

        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot,
            gptkOriginalsDXGI: originalsDXGI,
            gptkPayloadIsDeployed: true
        )

        XCTAssertTrue(exists(dxgi("system32")))
        XCTAssertNotEqual(try markerWindow(dxgi("system32")), Data("Wine builtin DLL".utf8))
        XCTAssertTrue(try Wine.isNativePE(dxgi("system32")))
    }

    /// The deploy replaces DXMT residue rather than leaving it behind.
    func testDeployedPayloadReplacesExistingResidue() throws {
        try writeOriginals(builtinFake("stored-original"))
        try nativeFake("dxmt-64").write(to: dxgi("system32"))

        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot,
            gptkOriginalsDXGI: originalsDXGI,
            gptkPayloadIsDeployed: true
        )

        XCTAssertTrue(try Wine.isNativePE(dxgi("system32")))
        XCTAssertNotEqual(try Data(contentsOf: dxgi("system32")), nativeFake("dxmt-64"))
    }

    /// GPTK deploys forwarders into `x86_64-windows` only, so the 32-bit
    /// builtin is still wine's own and the stored 64-bit original must not be
    /// written into syswow64.
    func testDeployedPayloadLeavesSysWOW64Alone() throws {
        try writeOriginals(builtinFake("stored-original"))

        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot,
            gptkOriginalsDXGI: originalsDXGI,
            gptkPayloadIsDeployed: true
        )

        XCTAssertFalse(exists(dxgi("syswow64")))
    }

    /// The stale-store case: `originals/` survives from a previous engine but
    /// the payload is gone, so the builtin is wine's own again and residue in
    /// *both* arches has to go. A store-keyed predicate would misread this as
    /// "GPTK active" and leave the 32-bit bad pairing in place. What replaces
    /// the residue is the runtime's own marked builtin, never an empty slot:
    /// wine's loader only finds a builtin through that placeholder (#163).
    func testStaleStoreReplacesResidueWithBuiltinInBothArches() throws {
        try writeOriginals(builtinFake("stale-original"))
        try nativeFake("dxmt-64").write(to: dxgi("system32"))
        try nativeFake("dxmt-32").write(to: dxgi("syswow64"))

        try Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot,
            gptkOriginalsDXGI: originalsDXGI,
            gptkPayloadIsDeployed: false,
            libraryFolder: makeRuntime()
        )

        XCTAssertEqual(try Data(contentsOf: dxgi("system32")), builtinFake("builtin-x86_64-windows"))
        XCTAssertEqual(try Data(contentsOf: dxgi("syswow64")), builtinFake("builtin-i386-windows"))
        XCTAssertFalse(try Wine.isNativePE(dxgi("system32")))
        XCTAssertFalse(try Wine.isNativePE(dxgi("syswow64")))
    }

    /// Without the payload, wine's builtin-marked placeholder must survive a
    /// DXVK launch: deleting it is a per-launch prefix mutation wineboot only
    /// has to undo.
    func testNotDeployedKeepsBuiltinPlaceholder() throws {
        try builtinFake("wine-fake").write(to: dxgi("system32"))

        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot,
            gptkOriginalsDXGI: originalsDXGI,
            gptkPayloadIsDeployed: false,
            libraryFolder: noRuntime
        )

        XCTAssertTrue(exists(dxgi("system32")))
        XCTAssertEqual(try Data(contentsOf: dxgi("system32")), builtinFake("wine-fake"))
    }

    /// A deployed payload with no stored dxgi backup has nothing to install;
    /// the prefix is left as-is rather than emptied.
    func testDeployedPayloadWithoutStoredOriginalIsANoOp() throws {
        try builtinFake("wine-fake").write(to: dxgi("system32"))

        Wine.reconcileDXGIForDXVK(
            prefixRoot: prefixRoot,
            gptkOriginalsDXGI: originalsDXGI,
            gptkPayloadIsDeployed: true
        )

        XCTAssertEqual(try Data(contentsOf: dxgi("system32")), builtinFake("wine-fake"))
    }

    // MARK: - Placeholder restore

    /// A runtime folder holding no builtins: removal then has nothing to put
    /// back, which is the behaviour the removal tests above pin down.
    private var noRuntime: URL { tempDir.appending(path: "no-runtime") }

    /// A runtime folder laid out like an installed WhiskyWine, carrying a
    /// marked builtin dxgi for each arch.
    private func makeRuntime() throws -> URL {
        let root = tempDir.appending(path: "runtime")
        for arch in ["x86_64-windows", "i386-windows"] {
            let dir = root.appending(path: "Wine/lib/wine/\(arch)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try builtinFake("builtin-\(arch)").write(to: dir.appending(path: "dxgi.dll"))
        }
        return root
    }

    /// Wine's loader only reaches a builtin through its system32 placeholder,
    /// so clearing residue must leave the runtime's own marked copy behind,
    /// not an empty slot that makes `dxgi.dll` unloadable (#163).
    func testRemovedResidueIsReplacedByBuiltinPlaceholder() throws {
        try nativeFake("dxmt64").write(to: dxgi("system32"))
        try nativeFake("dxmt32").write(to: dxgi("syswow64"))

        try Wine.removeStaleNativeDXGI(prefixRoot: prefixRoot, libraryFolder: makeRuntime())

        XCTAssertEqual(try Data(contentsOf: dxgi("system32")), builtinFake("builtin-x86_64-windows"))
        XCTAssertEqual(try Data(contentsOf: dxgi("syswow64")), builtinFake("builtin-i386-windows"))
        XCTAssertFalse(try Wine.isNativePE(dxgi("system32")))
        XCTAssertFalse(try Wine.isNativePE(dxgi("syswow64")))
    }

    /// A marked builtin already in place is the correct state and is not
    /// rewritten, so a good bottle stays off the prefix-mutation path.
    func testExistingBuiltinPlaceholderIsNotRewritten() throws {
        try builtinFake("already-there").write(to: dxgi("system32"))

        try Wine.removeStaleNativeDXGI(prefixRoot: prefixRoot, libraryFolder: makeRuntime())

        XCTAssertEqual(try Data(contentsOf: dxgi("system32")), builtinFake("already-there"))
    }
}
