//
//  ClipboardManagerTests.swift
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

import AppKit
@testable import WhiskyKit
import XCTest

final class ClipboardManagerTests: XCTestCase {
    var clipboardManager: ClipboardManager!

    override func setUp() async throws {
        try await super.setUp()
        clipboardManager = ClipboardManager.shared

        // Clear clipboard before each test
        clipboardManager.clear()
    }

    override func tearDown() async throws {
        // Clear clipboard after each test
        clipboardManager.clear()
        try await super.tearDown()
    }

    // MARK: - Content Querying Tests

    func testGetContentEmpty() {
        let content = clipboardManager.getContent()

        switch content {
        case .empty:
            XCTAssertTrue(true, "Content should be empty")
        default:
            XCTFail("Content should be empty, got \(content)")
        }
    }

    func testGetContentText() {
        let testText = "Hello, World!"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(testText, forType: .string)

        let content = clipboardManager.getContent()

        switch content {
        case let .text(text):
            XCTAssertEqual(text, testText, "Text content should match")
        default:
            XCTFail("Content should be text, got \(content)")
        }
    }

    func testGetContentImage() throws {
        // Create an image with actual pixel data (required for headless CI environments)
        let testImage = NSImage(size: NSSize(width: 10, height: 10))
        testImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        testImage.unlockFocus()

        guard let tiffData = testImage.tiffRepresentation, !tiffData.isEmpty else {
            throw XCTSkip("Skipping image test in headless environment (no display available)")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)

        let content = clipboardManager.getContent()

        switch content {
        case .image:
            XCTAssertTrue(true, "Content should be image")
        default:
            XCTFail("Content should be image, got \(content)")
        }
    }

    func testGetContentOther() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(rawValue: "com.custom.type"))

        let content = clipboardManager.getContent()

        switch content {
        case .other:
            XCTAssertTrue(true, "Content should be other")
        default:
            XCTFail("Content should be other, got \(content)")
        }
    }

    func testGetSize() {
        let testText = "Hello, World!"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(testText, forType: .string)

        let size = clipboardManager.getSize()

        XCTAssertEqual(size, testText.utf8.count, "Size should match text byte count")
    }

    func testGetSizeEmpty() {
        let size = clipboardManager.getSize()

        XCTAssertEqual(size, 0, "Size should be 0 for empty clipboard")
    }

    func testGetSizeImage() throws {
        // Create an image with actual pixel data (required for headless CI environments)
        let testImage = NSImage(size: NSSize(width: 10, height: 10))
        testImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        testImage.unlockFocus()

        guard let tiffData = testImage.tiffRepresentation, !tiffData.isEmpty else {
            throw XCTSkip("Skipping image test in headless environment (no display available)")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)

        let size = clipboardManager.getSize()

        XCTAssertGreaterThan(size, 0, "Size should be greater than 0 for image")
    }

    func testIsLarge() {
        let largeText = String(repeating: "A", count: 11_000) // > 10 KB
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(largeText, forType: .string)

        XCTAssertTrue(clipboardManager.isLarge(), "Clipboard should be considered large")
    }

    func testIsNotLarge() {
        let smallText = "Hello, World!"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(smallText, forType: .string)

        XCTAssertFalse(clipboardManager.isLarge(), "Clipboard should not be considered large")
    }

    func testLargeContentThreshold() {
        XCTAssertEqual(
            ClipboardManager.largeContentThreshold,
            10 * 1_024,
            "Large content threshold should be 10 KB"
        )
    }

    // MARK: - Modification Tests

    func testClearClipboard() {
        let testText = "Hello, World!"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(testText, forType: .string)

        let contentBefore = clipboardManager.getContent()
        switch contentBefore {
        case .empty:
            XCTFail("Content should not be empty before clear")
        default:
            break
        }

        clipboardManager.clear()

        let contentAfter = clipboardManager.getContent()
        switch contentAfter {
        case .empty:
            XCTAssertTrue(true, "Content should be empty after clear")
        default:
            XCTFail("Content should be empty after clear, got \(contentAfter)")
        }
    }

    func testClearEmptyClipboard() {
        // Should not crash
        clipboardManager.clear()

        let content = clipboardManager.getContent()
        switch content {
        case .empty:
            XCTAssertTrue(true, "Content should be empty")
        default:
            XCTFail("Content should be empty, got \(content)")
        }
    }

    // MARK: - ClipboardContent Tests

    func testClipboardContentSizeInBytesText() {
        let testText = "Hello, World!"
        let content = ClipboardManager.ClipboardContent.text(testText)

        XCTAssertEqual(content.sizeInBytes, testText.utf8.count, "Size should match text byte count")
    }

    func testClipboardContentSizeInBytesEmpty() {
        let content = ClipboardManager.ClipboardContent.empty

        XCTAssertEqual(content.sizeInBytes, 0, "Size should be 0 for empty content")
    }

    func testClipboardContentSizeInBytesImage() throws {
        // Create an image with actual pixel data (required for headless CI environments)
        let testImage = NSImage(size: NSSize(width: 10, height: 10))
        testImage.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        testImage.unlockFocus()

        guard testImage.tiffRepresentation != nil else {
            throw XCTSkip("Skipping image test in headless environment (no display available)")
        }

        let content = ClipboardManager.ClipboardContent.image(testImage)

        XCTAssertGreaterThan(content.sizeInBytes, 0, "Size should be greater than 0 for image")
    }

    func testClipboardContentSizeInBytesOther() {
        let content = ClipboardManager.ClipboardContent.other

        XCTAssertEqual(content.sizeInBytes, 0, "Size should be 0 for other content")
    }
}
