//
//  ProcessExtensionTests.swift
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
@testable import WhiskyKit
import XCTest

// MARK: - FileHandle.nextLine Tests

final class FileHandleNextLineTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appending(path: "nextline_\(UUID().uuidString).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testNextLineWithContent() throws {
        try Data("Hello, World!".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let line = handle.nextLine()
        XCTAssertEqual(line, "Hello, World!")
    }

    func testNextLineWithEmptyFile() throws {
        try Data().write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let line = handle.nextLine()
        XCTAssertNil(line)
    }

    func testNextLineWithMultipleLines() throws {
        try Data("Line 1\nLine 2\nLine 3".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        // First call gets all available data
        let line = handle.nextLine()
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("Line 1") ?? false)
    }

    func testNextLineWithUnicodeContent() throws {
        try Data("日本語テスト 🍷".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let line = handle.nextLine()
        XCTAssertEqual(line, "日本語テスト 🍷")
    }
}
