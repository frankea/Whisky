//
//  VCRuntimeFallbackTests.swift
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

final class VCRuntimeFallbackTests: XCTestCase {
    private var bottleURL: URL!

    private func definition(_ id: String) throws -> DependencyDefinition {
        try XCTUnwrap(DependencyDefinition.standardDependencies.first { $0.id == id })
    }

    override func setUpWithError() throws {
        bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "VCRuntimeFallbackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bottleURL)
    }

    /// Creates empty DLL files in a system directory under drive_c.
    private func placeDLLs(_ names: [String], in directory: String) throws {
        let directoryURL = bottleURL
            .appending(path: "drive_c")
            .appending(path: directory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for name in names {
            FileManager.default.createFile(
                atPath: directoryURL.appending(path: name).path(percentEncoded: false),
                contents: Data()
            )
        }
    }

    // MARK: - Regression Cases

    /// The vc_redist installer hung under wine, so winetricks.log never got
    /// the vcrun2019 entry -- but the runtime is in place (#233).
    func testDetectsInstallationWhenMarkerPresentButLogEntryMissing() throws {
        try placeDLLs(["mfc140.dll"], in: "windows/system32")

        XCTAssertTrue(
            try VCRuntimeFallback.detectsInstallation(
                definition: definition("vcruntime"),
                missingVerbs: ["vcrun2019"],
                bottleURL: bottleURL
            )
        )
    }

    /// A fresh prefix carries msvcp140.dll and vcruntime140.dll as Wine
    /// builtins; their presence must not count as an installed runtime.
    func testNotDetectedOnFreshPrefixWithWineBuiltins() throws {
        try placeDLLs(["msvcp140.dll", "vcruntime140.dll"], in: "windows/system32")
        try placeDLLs(["msvcp140.dll", "vcruntime140.dll"], in: "windows/syswow64")

        XCTAssertFalse(
            try VCRuntimeFallback.detectsInstallation(
                definition: definition("vcruntime"),
                missingVerbs: ["vcrun2019"],
                bottleURL: bottleURL
            )
        )
    }

    // MARK: - Scoping

    /// A bottle whose log already says installed must not be probed.
    func testDoesNotApplyWhenNoVerbsAreMissing() throws {
        try placeDLLs(["mfc140.dll"], in: "windows/system32")

        XCTAssertFalse(
            try VCRuntimeFallback.detectsInstallation(
                definition: definition("vcruntime"),
                missingVerbs: [],
                bottleURL: bottleURL
            )
        )
    }

    func testDoesNotApplyToOtherDefinitions() throws {
        try placeDLLs(["mfc140.dll"], in: "windows/system32")
        let dotnet = try definition("dotnet48")

        XCTAssertFalse(
            VCRuntimeFallback.detectsInstallation(
                definition: dotnet,
                missingVerbs: ["dotnet48"],
                bottleURL: bottleURL
            )
        )
    }

    // MARK: - Marker Location

    func testNotDetectedWhenMarkerAbsent() throws {
        try placeDLLs([], in: "windows/system32")

        XCTAssertFalse(
            try VCRuntimeFallback.detectsInstallation(
                definition: definition("vcruntime"),
                missingVerbs: ["vcrun2019"],
                bottleURL: bottleURL
            )
        )
    }

    /// mfc140.dll in syswow64 alone is the #233 partial install (the x86
    /// half landed, the x64 half hung); it must stay not-installed so the
    /// rerun remains offered as the repair path.
    func testMarkerInSyswow64AloneDoesNotCount() throws {
        try placeDLLs(["mfc140.dll"], in: "windows/syswow64")

        XCTAssertFalse(
            try VCRuntimeFallback.detectsInstallation(
                definition: definition("vcruntime"),
                missingVerbs: ["vcrun2019"],
                bottleURL: bottleURL
            )
        )
    }
}
