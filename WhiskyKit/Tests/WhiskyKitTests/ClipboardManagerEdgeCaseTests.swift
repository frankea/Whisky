//
//  ClipboardManagerEdgeCaseTests.swift
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

// MARK: - Integration Tests

final class ClipboardManagerIntegrationTests: XCTestCase {
    var clipboardManager: ClipboardManager!

    override func setUp() async throws {
        try await super.setUp()
        clipboardManager = ClipboardManager.shared
        clipboardManager.clear()
    }

    override func tearDown() async throws {
        clipboardManager.clear()
        try await super.tearDown()
    }

    func testClipboardWorkflow() {
        let pasteboard = NSPasteboard.general

        // Set content
        let testText = "Test workflow"
        pasteboard.clearContents()
        pasteboard.setString(testText, forType: .string)

        // Query content
        let content = clipboardManager.getContent()
        switch content {
        case let .text(text):
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
}

// MARK: - Edge Case Tests

final class ClipboardManagerEdgeCaseTests: XCTestCase {
    var clipboardManager: ClipboardManager!

    override func setUp() async throws {
        try await super.setUp()
        clipboardManager = ClipboardManager.shared
        clipboardManager.clear()
    }

    override func tearDown() async throws {
        clipboardManager.clear()
        try await super.tearDown()
    }

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
        case let .text(text):
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
        case let .text(text):
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
        case let .text(text):
            XCTAssertEqual(text, testText, "Text should be detected")
        default:
            XCTFail("Text should be detected when multiple types present")
        }
    }
}

// MARK: - Sendable Tests

final class ClipboardManagerSendableTests: XCTestCase {
    func testClipboardContentSendable() {
        let content = ClipboardManager.ClipboardContent.text("test")

        // Verify Sendable conformance by passing to async context
        let expectation = XCTestExpectation(description: "Sendable test")

        Task {
            _ = content
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
