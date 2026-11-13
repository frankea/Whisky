//
//  VCRedistDetectorTests.swift
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

final class VCRedistDetectorTests: XCTestCase {
    private var prefixURL = URL(filePath: "/dev/null")

    override func setUpWithError() throws {
        try super.setUpWithError()
        prefixURL = FileManager.default.temporaryDirectory
            .appending(path: "VCRedistDetectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: prefixURL)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// A PE header whose DOS stub sits at 0x40, the way Microsoft's linker emits it.
    private var nativeDLL: Data {
        Data("MZ".utf8) + Data(count: 0x3E) + Data("This program cannot be run in DOS mode.".utf8)
    }

    /// A PE header carrying one of Wine's markers at 0x40.
    private func wineDLL(_ marker: String) -> Data {
        Data("MZ".utf8) + Data(count: 0x3E) + Data(marker.utf8) + Data(count: 16)
    }

    private func write(_ data: Data, named name: String, in folder: String) throws {
        let directory = prefixURL.appending(path: "drive_c").appending(path: "windows").appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: name))
    }

    // MARK: - Tests

    func testFreshPrefixWithoutSystemFoldersIsNotInstalled() {
        XCTAssertFalse(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }

    func testWineBuiltinCopiesAreNotTheRuntime() throws {
        for folder in ["system32", "syswow64"] {
            try write(wineDLL("Wine builtin DLL"), named: "msvcp140.dll", in: folder)
            try write(wineDLL("Wine builtin DLL"), named: "vcruntime140.dll", in: folder)
        }
        XCTAssertFalse(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }

    func testWinePlaceholderCopiesAreNotTheRuntime() throws {
        try write(wineDLL("Wine placeholder DLL"), named: "msvcp140.dll", in: "system32")
        try write(wineDLL("Wine placeholder DLL"), named: "vcruntime140.dll", in: "system32")
        XCTAssertFalse(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }

    func testNativeDLLsInSystem32AreTheRuntime() throws {
        try write(nativeDLL, named: "msvcp140.dll", in: "system32")
        try write(nativeDLL, named: "vcruntime140.dll", in: "system32")
        XCTAssertTrue(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }

    func testNativeDLLsInSysWOW64AreTheRuntime() throws {
        try write(wineDLL("Wine builtin DLL"), named: "msvcp140.dll", in: "system32")
        try write(nativeDLL, named: "msvcp140.dll", in: "syswow64")
        try write(nativeDLL, named: "vcruntime140.dll", in: "syswow64")
        XCTAssertTrue(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }

    func testOneNativeDLLAloneIsNotTheRuntime() throws {
        try write(nativeDLL, named: "msvcp140.dll", in: "system32")
        try write(wineDLL("Wine builtin DLL"), named: "vcruntime140.dll", in: "system32")
        XCTAssertFalse(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }

    func testDLLsSplitAcrossFoldersAreNotTheRuntime() throws {
        try write(nativeDLL, named: "msvcp140.dll", in: "system32")
        try write(nativeDLL, named: "vcruntime140.dll", in: "syswow64")
        XCTAssertFalse(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }

    func testTruncatedOrNonPEFilesAreNotNative() throws {
        try write(Data("MZ".utf8), named: "msvcp140.dll", in: "system32")
        try write(Data(count: 0x80), named: "vcruntime140.dll", in: "system32")
        let system32 = prefixURL.appending(path: "drive_c").appending(path: "windows").appending(path: "system32")
        XCTAssertFalse(VCRedistDetector.isNativePE(system32.appending(path: "msvcp140.dll")))
        XCTAssertFalse(VCRedistDetector.isNativePE(system32.appending(path: "vcruntime140.dll")))
        XCTAssertFalse(VCRedistDetector.isNativePE(system32.appending(path: "missing.dll")))
        XCTAssertFalse(VCRedistDetector.isInstalled(prefixURL: prefixURL))
    }
}
