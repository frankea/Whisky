//
//  BottleClipboardCheckTests.swift
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

/// The bottle-level clipboard check every launch path applies. Only the
/// outcomes that leave the clipboard alone are exercised: the others clear the
/// host's clipboard or put up a modal alert.
@MainActor
final class BottleClipboardCheckTests: XCTestCase {
    private var bottleURL: URL!
    private var bottle: Bottle!

    override func setUp() async throws {
        try await super.setUp()
        bottleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-bottle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: bottleURL, isAvailable: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: bottleURL)
        try await super.tearDown()
    }

    func testNeverPolicyIsSafe() {
        bottle.settings.clipboardPolicy = .never

        guard case .safe = bottle.performClipboardCheck() else {
            return XCTFail("Expected the Never policy to leave the clipboard alone")
        }
    }

    /// Nothing on any clipboard exceeds this, so the policy never has to act.
    func testContentBelowTheBottleThresholdIsSafe() {
        bottle.settings.clipboardPolicy = .alwaysClear
        bottle.settings.clipboardThreshold = Int.max

        guard case .safe = bottle.performClipboardCheck() else {
            return XCTFail("Expected content under the bottle's threshold to be left alone")
        }
    }

    func testProgramUsesItsBottlesPolicy() {
        bottle.settings.clipboardPolicy = .never
        let program = Program(url: bottleURL.appendingPathComponent("game.exe"), bottle: bottle, peFile: nil)

        guard case .safe = program.performClipboardCheck() else {
            return XCTFail("Expected the program to apply its bottle's Never policy")
        }
    }
}
