//
//  DependencyInstallAttemptTests.swift
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

final class DependencyInstallAttemptTests: XCTestCase {
    // MARK: - Output Tail Round-Trip

    func testOutputTailSurvivesPlistRoundTrip() throws {
        let attempt = DependencyInstallAttempt(
            definitionId: "vcruntime",
            verbsAttempted: ["vcrun2019"],
            timestamp: Date(),
            success: false,
            exitCode: 1,
            outputTail: "SHA256 mismatch!\nExpected: 49545cb0"
        )

        let data = try PropertyListEncoder().encode(attempt)
        let decoded = try PropertyListDecoder().decode(DependencyInstallAttempt.self, from: data)

        XCTAssertEqual(decoded.outputTail, "SHA256 mismatch!\nExpected: 49545cb0")
        XCTAssertEqual(decoded.exitCode, 1)
    }

    func testEntriesWithoutOutputTailStillDecode() throws {
        // Entries written before the outputTail field existed.
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>definitionId</key><string>vcruntime</string>
            <key>verbsAttempted</key><array><string>vcrun2019</string></array>
            <key>timestamp</key><date>2026-08-28T19:18:23Z</date>
            <key>success</key><false/>
            <key>exitCode</key><integer>1</integer>
        </dict>
        </plist>
        """

        let decoded = try PropertyListDecoder().decode(
            DependencyInstallAttempt.self,
            from: Data(plist.utf8)
        )

        XCTAssertNil(decoded.outputTail)
        XCTAssertEqual(decoded.exitCode, 1)
    }

    // MARK: - Bounded Tail

    func testBoundedTailReturnsNilForEmptyInput() {
        XCTAssertNil(DependencyInstallAttempt.boundedTail(of: []))
    }

    func testBoundedTailKeepsAllLinesWhenUnderBudget() {
        let lines = ["one", "two", "three"]
        XCTAssertEqual(DependencyInstallAttempt.boundedTail(of: lines), "one\ntwo\nthree")
    }

    func testBoundedTailKeepsNewestLinesWithinBudget() {
        let filler = String(repeating: "x", count: 1_000)
        let lines = (0 ..< 10).map { "\($0) \(filler)" }

        let tail = try? XCTUnwrap(DependencyInstallAttempt.boundedTail(of: lines))
        let kept = tail?.components(separatedBy: "\n") ?? []

        XCTAssertLessThanOrEqual(
            tail?.utf8.count ?? .max,
            DependencyInstallAttempt.maxOutputTailBytes
        )
        // Newest lines survive, oldest are dropped.
        XCTAssertEqual(kept.last, lines.last)
        XCTAssertFalse(kept.contains(lines.first ?? ""))
    }

    func testBoundedTailTruncatesSingleOversizedLine() {
        let oversized = String(repeating: "y", count: 10_000)

        let tail = DependencyInstallAttempt.boundedTail(of: [oversized])

        XCTAssertEqual(tail?.utf8.count, DependencyInstallAttempt.maxOutputTailBytes)
        XCTAssertTrue(tail?.allSatisfy { $0 == "y" } ?? false)
    }

    func testBoundedTailSurvivesCutInsideMultiByteCharacter() {
        // 2-byte characters with an odd byte budget guarantee the cut lands
        // mid-character; the tail must still decode.
        let oversized = String(repeating: "ä", count: 5_000)

        let tail = DependencyInstallAttempt.boundedTail(of: [oversized])

        XCTAssertNotNil(tail)
        XCTAssertLessThanOrEqual(
            tail?.utf8.count ?? .max,
            DependencyInstallAttempt.maxOutputTailBytes
        )
        XCTAssertTrue(tail?.allSatisfy { $0 == "ä" } ?? false)
    }
}
