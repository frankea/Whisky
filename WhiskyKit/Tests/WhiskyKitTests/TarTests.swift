//
//  TarTests.swift
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

// swiftlint:disable file_length
import Foundation
@testable import WhiskyKit
import XCTest

// MARK: - TarError Tests

final class TarErrorTests: XCTestCase {
    func testPathTraversalErrorDescription() {
        let error = TarError.pathTraversal(path: "../../../etc/passwd")
        XCTAssertEqual(
            error.errorDescription,
            "Archive contains unsafe path that escapes target directory: ../../../etc/passwd"
        )
    }

    func testUnsafeSymlinkErrorDescription() {
        let error = TarError.unsafeSymlink(path: "malicious_link", target: "/etc/passwd")
        XCTAssertEqual(
            error.errorDescription,
            "Archive contains symlink 'malicious_link' with unsafe target '/etc/passwd'"
        )
    }

    func testCommandFailedErrorDescription() {
        let error = TarError.commandFailed(output: "tar: Error opening archive")
        XCTAssertEqual(
            error.errorDescription,
            "Tar command failed: tar: Error opening archive"
        )
    }

    func testTarErrorIsLocalizedError() {
        let error = TarError.pathTraversal(path: "test")
        XCTAssertNotNil(error.errorDescription)
    }
}

// MARK: - Tar Integration Tests

final class TarIntegrationTests: XCTestCase {
    var tempDir: URL!
    var sourceDir: URL!
    var extractDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "tar_test_\(UUID().uuidString)")
        sourceDir = tempDir.appending(path: "source")
        extractDir = tempDir.appending(path: "extract")

        try? FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testTarAndUntarRoundTrip() throws {
        let testFile = sourceDir.appending(path: "test.txt")
        try Data("Hello, World!".utf8).write(to: testFile)

        let tarURL = tempDir.appending(path: "test.tar.gz")

        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path(percentEncoded: false)))

        try Tar.untar(tarBall: tarURL, toURL: extractDir)

        let extractedItems = try FileManager.default.contentsOfDirectory(
            at: extractDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(extractedItems.isEmpty)
    }

    func testUntarRoundTripWithDayFirstDateLocale() throws {
        // bsdtar formats verbose listing dates per locale; en_GB prints
        // "13 Jun 09:54" instead of "Jun 13 09:54". Archive validation must
        // not depend on the host locale (see #139).
        let previous = getenv("LC_ALL").map { String(cString: $0) }
        setenv("LC_ALL", "en_GB.UTF-8", 1)
        defer {
            if let previous {
                setenv("LC_ALL", previous, 1)
            } else {
                unsetenv("LC_ALL")
            }
        }

        let testFile = sourceDir.appending(path: "test.txt")
        try Data("Hello, World!".utf8).write(to: testFile)

        let tarURL = tempDir.appending(path: "locale.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertNoThrow(try Tar.untar(tarBall: tarURL, toURL: extractDir))
    }

    func testUntarPreservesInternalSymlink() throws {
        try Data("Hello, World!".utf8).write(to: sourceDir.appending(path: "test.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: sourceDir.appending(path: "link").path(percentEncoded: false),
            withDestinationPath: "test.txt"
        )

        let tarURL = tempDir.appending(path: "symlink.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)
        try Tar.untar(tarBall: tarURL, toURL: extractDir)

        // The extracted tree must still contain the (safe, internal) symlink.
        let enumerator = FileManager.default.enumerator(
            at: extractDir,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        )
        let symlinks = (enumerator?.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
            return isLink ? url : nil
        }) ?? []
        XCTAssertEqual(symlinks.count, 1)
    }

    func testUntarRejectsAbsoluteSymlink() throws {
        try Data("decoy".utf8).write(to: sourceDir.appending(path: "decoy.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: sourceDir.appending(path: "evil").path(percentEncoded: false),
            withDestinationPath: "/etc/passwd"
        )

        let tarURL = tempDir.appending(path: "abs-symlink.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertThrowsError(try Tar.untar(tarBall: tarURL, toURL: extractDir)) { error in
            guard case .unsafeSymlink = error as? TarError else {
                return XCTFail("Expected unsafeSymlink error, got \(error)")
            }
        }

        // Extraction is staged: a rejected archive leaves the destination untouched.
        let contents = try FileManager.default.contentsOfDirectory(
            at: extractDir, includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty)
    }

    func testUntarRejectsEscapingRelativeSymlink() throws {
        // Deep enough to escape any staging root regardless of temp-path depth.
        let escape = String(repeating: "../", count: 40) + "etc"
        try FileManager.default.createSymbolicLink(
            atPath: sourceDir.appending(path: "evil").path(percentEncoded: false),
            withDestinationPath: escape
        )

        let tarURL = tempDir.appending(path: "rel-symlink.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertThrowsError(try Tar.untar(tarBall: tarURL, toURL: extractDir)) { error in
            guard case .unsafeSymlink = error as? TarError else {
                return XCTFail("Expected unsafeSymlink error, got \(error)")
            }
        }
    }

    func testUntarRejectsCraftedTraversalPath() throws {
        // Build an archive whose member path literally contains `../` using
        // tar -P, which stores the path verbatim instead of sanitizing it.
        try Data("outside".utf8).write(to: tempDir.appending(path: "escape.txt"))

        let tarURL = tempDir.appending(path: "traversal.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czPf", tarURL.path(percentEncoded: false),
            "-C", sourceDir.path(percentEncoded: false),
            "../escape.txt"
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        XCTAssertThrowsError(try Tar.untar(tarBall: tarURL, toURL: extractDir)) { error in
            guard case .pathTraversal = error as? TarError else {
                return XCTFail("Expected pathTraversal error, got \(error)")
            }
        }
    }

    func testTarEntriesAreRelativeToTheFolder() throws {
        let sourceDir = tempDir.appendingPathComponent("relative-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "x".write(to: sourceDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let tarURL = tempDir.appendingPathComponent("relative.tar.gz")

        try Tar.tar(folder: sourceDir, toURL: tarURL)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tzf", tarURL.path]
        process.standardOutput = pipe
        try process.run()
        let listing = try String(data: pipe.fileHandleForReading.readToEnd() ?? Data(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        let entries = listing.split(separator: "\n").map(String.init)
        XCTAssertTrue(entries.contains("relative-source/file.txt"), "entries: \(entries)")
        XCTAssertFalse(entries.contains { $0.hasPrefix("/") || $0.hasPrefix("Users/") || $0.hasPrefix("private/") })
        XCTAssertFalse(entries.contains { $0.contains("._") }, "no AppleDouble entries: \(entries)")
    }

    func testTarWithMultipleFiles() throws {
        try Data("File 1 content".utf8).write(to: sourceDir.appending(path: "file1.txt"))
        try Data("File 2 content".utf8).write(to: sourceDir.appending(path: "file2.txt"))
        try Data("File 3 content".utf8).write(to: sourceDir.appending(path: "file3.txt"))

        let tarURL = tempDir.appending(path: "multi.tar.gz")

        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path(percentEncoded: false)))
    }

    func testTarWithNestedDirectories() throws {
        let subDir = sourceDir.appending(path: "subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data("Nested file".utf8).write(to: subDir.appending(path: "nested.txt"))

        let tarURL = tempDir.appending(path: "nested.tar.gz")

        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path(percentEncoded: false)))
    }

    func testUntarWithInvalidArchive() throws {
        let invalidTar = tempDir.appending(path: "invalid.tar.gz")
        try Data("not a tar file".utf8).write(to: invalidTar)

        XCTAssertThrowsError(try Tar.untar(tarBall: invalidTar, toURL: extractDir)) { error in
            if let tarError = error as? TarError {
                if case .commandFailed = tarError {
                } else {
                    XCTFail("Expected commandFailed error")
                }
            }
        }
    }

    func testUntarNonExistentFile() {
        let nonExistent = tempDir.appending(path: "nonexistent.tar.gz")

        XCTAssertThrowsError(try Tar.untar(tarBall: nonExistent, toURL: extractDir))
    }

    func testTarEmptyDirectory() throws {
        let emptyDir = tempDir.appending(path: "empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let tarURL = tempDir.appending(path: "empty.tar.gz")

        try Tar.tar(folder: emptyDir, toURL: tarURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path(percentEncoded: false)))
    }

    func testTarWithSpecialCharactersInFilename() throws {
        let specialFile = sourceDir.appending(path: "file with spaces.txt")
        try Data("content".utf8).write(to: specialFile)

        let tarURL = tempDir.appending(path: "special.tar.gz")

        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path(percentEncoded: false)))
    }
}

// MARK: - Tar Path Traversal Security Tests

final class TarPathTraversalTests: XCTestCase {
    var tempDir: URL!
    var extractDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "tar_security_\(UUID().uuidString)")
        extractDir = tempDir.appending(path: "extract")

        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testValidArchiveExtraction() throws {
        let sourceDir = tempDir.appending(path: "source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("safe content".utf8).write(to: sourceDir.appending(path: "safe.txt"))

        let tarURL = tempDir.appending(path: "safe.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertNoThrow(try Tar.untar(tarBall: tarURL, toURL: extractDir))
    }

    func testTarBinaryPath() {
        let tarBinary = URL(fileURLWithPath: "/usr/bin/tar")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tarBinary.path))
    }
}

// MARK: - Tar Command Tests

final class TarCommandTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "tar_cmd_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testTarCreatesCompressedArchive() throws {
        let sourceDir = tempDir.appending(path: "source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let largeContent = String(repeating: "A", count: 10_000)
        try Data(largeContent.utf8).write(to: sourceDir.appending(path: "large.txt"))

        let tarURL = tempDir.appending(path: "compressed.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)

        let tarData = try Data(contentsOf: tarURL)
        XCTAssertLessThan(tarData.count, largeContent.count)
    }

    func testTarPreservesDirectoryStructure() throws {
        let sourceDir = tempDir.appending(path: "source")
        let subDir = sourceDir.appending(path: "level1/level2/level3")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try Data("deep file".utf8).write(to: subDir.appending(path: "deep.txt"))

        let tarURL = tempDir.appending(path: "deep.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)

        let extractDir = tempDir.appending(path: "extract")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try Tar.untar(tarBall: tarURL, toURL: extractDir)

        let extractedItems = try FileManager.default.contentsOfDirectory(
            at: extractDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(extractedItems.isEmpty)
    }

    func testTarWithBinaryContent() throws {
        let sourceDir = tempDir.appending(path: "source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        var binaryData = Data()
        for byteValue: UInt8 in 0 ... 255 {
            binaryData.append(byteValue)
        }
        try binaryData.write(to: sourceDir.appending(path: "binary.bin"))

        let tarURL = tempDir.appending(path: "binary.tar.gz")
        try Tar.tar(folder: sourceDir, toURL: tarURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path(percentEncoded: false)))
    }
}

// MARK: - String Error Conformance Test

final class StringErrorConformanceTests: XCTestCase {
    func testStringIsError() {
        let errorString: Error = "This is an error"
        XCTAssertNotNil(errorString)
    }

    func testStringErrorCanBeThrown() {
        func throwingFunction() throws {
            throw "Custom error message"
        }

        XCTAssertThrowsError(try throwingFunction()) { error in
            XCTAssertTrue(error is String)
        }
    }

    func testStringErrorCastable() {
        let errorString: Error = "Test error description"
        if let stringError = errorString as? String {
            XCTAssertEqual(stringError, "Test error description")
        } else {
            XCTFail("Expected error to be castable to String")
        }
    }
}
