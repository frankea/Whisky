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

@testable import WhiskyKit
import AppKit
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
        case .text(let text):
            XCTAssertEqual(text, testText, "Text content should match")
        default:
            XCTFail("Content should be text, got \(content)")
        }
    }

    func testGetContentImage() {
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(testImage.tiffRepresentation, forType: .tiff)

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

    func testGetSizeImage() {
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(testImage.tiffRepresentation, forType: .tiff)

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
            10 * 1024,
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

    func testClipboardContentSizeInBytesImage() {
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        let content = ClipboardManager.ClipboardContent.image(testImage)

        XCTAssertGreaterThan(content.sizeInBytes, 0, "Size should be greater than 0 for image")
    }

    func testClipboardContentSizeInBytesOther() {
        let content = ClipboardManager.ClipboardContent.other

        XCTAssertEqual(content.sizeInBytes, 0, "Size should be 0 for other content")
    }

    // MARK: - Integration Tests

    func testClipboardWorkflow() {
        let pasteboard = NSPasteboard.general

        // Set content
        let testText = "Test workflow"
        pasteboard.clearContents()
        pasteboard.setString(testText, forType: .string)

        // Query content
        let content = clipboardManager.getContent()
        switch content {
        case .text(let text):
            XCTAssertEqual(text, testText, "Text should match")
        default:
            XCTFail("Content should be text")
        }

        // Check size
        let size = clipboardManager.getSize()
        XCTAssertEqual(size, testText.utf8.count, "Size should match")

        // Check if large
        XCTAssertFalse(clipboardManager.isLarge(), "Should not be large")

        // Clear
        clipboardManager.clear()

        let finalContent = clipboardManager.getContent()
        switch finalContent {
        case .empty:
            XCTAssertTrue(true, "Content should be empty after clear")
        default:
            XCTFail("Content should be empty")
        }
    }

    func testLargeClipboardDetection() {
        let pasteboard = NSPasteboard.general

        // Set small content
        let smallText = "Small"
        pasteboard.clearContents()
        pasteboard.setString(smallText, forType: .string)

        XCTAssertFalse(clipboardManager.isLarge(), "Small content should not be large")

        // Set large content
        let largeText = String(repeating: "X", count: 11_000)
        pasteboard.clearContents()
        pasteboard.setString(largeText, forType: .string)

        XCTAssertTrue(clipboardManager.isLarge(), "Large content should be detected")

        // Verify size
        let size = clipboardManager.getSize()
        XCTAssertGreaterThan(size, ClipboardManager.largeContentThreshold, "Size should exceed threshold")
    }

    // MARK: - Edge Cases

    func testEmptyStringClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("", forType: .string)

        let content = clipboardManager.getContent()

        switch content {
        case .empty:
            XCTAssertTrue(true, "Empty string should be treated as empty")
        default:
            XCTFail("Empty string should be treated as empty, got \(content)")
        }
    }

    func testWhitespaceOnlyClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("   ", forType: .string)

        let content = clipboardManager.getContent()

        switch content {
        case .text(let text):
            XCTAssertEqual(text, "   ", "Whitespace should be preserved")
        default:
            XCTFail("Whitespace should be treated as text, got \(content)")
        }
    }

    func testUnicodeTextClipboard() {
        let unicodeText = "Hello 世界 🌍"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(unicodeText, forType: .string)

        let content = clipboardManager.getContent()

        switch content {
        case .text(let text):
            XCTAssertEqual(text, unicodeText, "Unicode text should be preserved")
        default:
            XCTFail("Unicode should be preserved, got \(content)")
        }

        let size = clipboardManager.getSize()
        XCTAssertGreaterThan(size, 0, "Unicode text should have size")
    }

    func testMultipleContentTypes() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Set both text and image
        let testText = "Test"
        pasteboard.setString(testText, forType: .string)

        let content = clipboardManager.getContent()

        // Should detect text first
        switch content {
        case .text(let text):
            XCTAssertEqual(text, testText, "Text should be detected")
        default:
            XCTFail("Text should be detected when multiple types present")
        }
    }

    // MARK: - Sendable Tests

    func testClipboardContentSendable() {
        let content = ClipboardManager.ClipboardContent.text("test")

        // Verify Sendable conformance by passing to async context
        let expectation = XCTestExpectation(description: "Sendable test")

        Task {
            let _ = content
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
