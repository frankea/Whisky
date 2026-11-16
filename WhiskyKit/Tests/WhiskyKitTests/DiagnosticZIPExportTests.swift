//
//  DiagnosticZIPExportTests.swift
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

final class DiagnosticZIPExportTests: XCTestCase {
    private var root = URL(filePath: "/dev/null")

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appending(path: "DiagnosticZIPExportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func contents(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    // MARK: - compressZIP

    func testCompressWritesTheArchive() throws {
        let content = root.appending(path: "content")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try Data("report".utf8).write(to: content.appending(path: "report.md"))
        let zip = root.appending(path: "out.zip")

        try DiagnosticExporter.compressZIP(from: content, to: zip)

        let data = try Data(contentsOf: zip)
        XCTAssertEqual(data.prefix(2), Data("PK".utf8))
    }

    func testCompressFailureIsReportedWithDittosStatus() {
        let missing = root.appending(path: "missing")
        let zip = root.appending(path: "out.zip")

        XCTAssertThrowsError(try DiagnosticExporter.compressZIP(from: missing, to: zip)) { error in
            guard case let .compressionFailed(status) = error as? DiagnosticExportError else {
                return XCTFail("Expected compressionFailed, got \(error)")
            }
            XCTAssertNotEqual(status, 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: zip.path(percentEncoded: false)))
    }

    func testCompressThatExitsCleanlyWithoutAnArchiveIsAFailure() {
        // /usr/bin/true exits 0 and writes nothing.
        XCTAssertThrowsError(
            try DiagnosticExporter.compressZIP(
                from: root,
                to: root.appending(path: "out.zip"),
                ditto: URL(fileURLWithPath: "/usr/bin/true")
            )
        ) { error in
            XCTAssertEqual(error as? DiagnosticExportError, .archiveMissing)
        }
    }

    // MARK: - saveArchive

    func testSaveMovesTheArchiveIntoPlace() throws {
        let archive = root.appending(path: "built.zip")
        try Data("new".utf8).write(to: archive)
        let destination = root.appending(path: "saved").appending(path: "Report.zip")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        try DiagnosticExporter.saveArchive(archive, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        XCTAssertEqual(try contents(of: destination.deletingLastPathComponent()), ["Report.zip"])
    }

    func testSaveReplacesAnExistingFileOnlyWithTheFinishedArchive() throws {
        let archive = root.appending(path: "built.zip")
        try Data("new".utf8).write(to: archive)
        let destination = root.appending(path: "Report.zip")
        try Data("old".utf8).write(to: destination)

        try DiagnosticExporter.saveArchive(archive, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        XCTAssertFalse(try contents(of: root).contains { $0.hasSuffix(".partial") })
    }

    func testMissingArchiveLeavesTheChosenFileAlone() throws {
        let destination = root.appending(path: "Report.zip")
        try Data("old".utf8).write(to: destination)

        XCTAssertThrowsError(try DiagnosticExporter.saveArchive(root.appending(path: "none.zip"), to: destination)) {
            XCTAssertEqual($0 as? DiagnosticExportError, .archiveMissing)
        }
        XCTAssertEqual(try Data(contentsOf: destination), Data("old".utf8))
    }

    func testUnwritableDestinationFolderLeavesTheChosenFileAlone() throws {
        let archive = root.appending(path: "built.zip")
        try Data("new".utf8).write(to: archive)
        let folder = root.appending(path: "locked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: "Report.zip")
        try Data("old".utf8).write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        XCTAssertThrowsError(try DiagnosticExporter.saveArchive(archive, to: destination))

        XCTAssertEqual(try Data(contentsOf: destination), Data("old".utf8))
        XCTAssertEqual(try contents(of: folder), ["Report.zip"])
    }

    // MARK: - exportZIP

    private var emptyDiagnosis: CrashDiagnosis {
        CrashDiagnosis(
            matches: [],
            categoryCounts: [:],
            primaryCategory: nil,
            primaryConfidence: nil,
            headline: nil,
            exitCode: 1,
            applicableRemediationIds: []
        )
    }

    @MainActor
    func testExportReplacesTheChosenFileWithAFinishedArchive() async throws {
        let bottleURL = root.appending(path: "Bottle")
        let programURL = bottleURL.appending(path: "drive_c").appending(path: "game.exe")
        try FileManager.default.createDirectory(
            at: programURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("exe".utf8).write(to: programURL)
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        let destination = root.appending(path: "Report.zip")
        try Data("old".utf8).write(to: destination)

        try await DiagnosticExporter.exportZIP(
            diagnosis: emptyDiagnosis,
            bottle: bottle,
            program: program,
            logFileURL: nil,
            timeline: nil,
            to: destination
        )

        XCTAssertEqual(try Data(contentsOf: destination).prefix(2), Data("PK".utf8))
        XCTAssertFalse(try contents(of: root).contains { $0.hasSuffix(".partial") })
    }

    @MainActor
    func testExportToAMissingFolderFailsWithoutLeavingAFile() async throws {
        let bottleURL = root.appending(path: "Bottle")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: bottleURL.appending(path: "game.exe"), bottle: bottle)
        let destination = root.appending(path: "gone").appending(path: "Report.zip")

        do {
            try await DiagnosticExporter.exportZIP(
                diagnosis: emptyDiagnosis,
                bottle: bottle,
                program: program,
                logFileURL: nil,
                timeline: nil,
                to: destination
            )
            XCTFail("Expected the export to fail")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        }
    }

    // MARK: - Error text

    func testErrorsDescribeThemselves() {
        XCTAssertNotNil(DiagnosticExportError.compressionFailed(status: 1).errorDescription)
        XCTAssertNotNil(DiagnosticExportError.archiveMissing.errorDescription)
    }
}
