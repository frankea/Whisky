//
//  StringCatalogTestSupport.swift
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
import XCTest

/// The app's string catalog, read from the repository, so WhiskyKit tests can
/// check that the keys WhiskyKit looks up exist there.
///
/// WhiskyKit's `String(localized:)` calls resolve against the app's main bundle,
/// which the test runner doesn't have. There a lookup finds no catalog and
/// returns its key with any arguments substituted, so the result of a lookup
/// names the key it used: `"audio.status.ok"`, or `"diagnostics.headline Crash 2"`
/// for a key with arguments.
enum StringCatalog {
    /// `Whisky/Localizable.xcstrings`, found from this file's location.
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // WhiskyKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // WhiskyKit
        .deletingLastPathComponent() // repository root
        .appending(path: "Whisky")
        .appending(path: "Localizable.xcstrings")

    /// Each catalog key and its English value (empty when the key is its own English).
    static let english: [String: String] = {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { return [:] }
        var result: [String: String] = [:]
        for (key, entry) in strings {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
            let englishRow = localizations?["en"] as? [String: Any]
            let unit = englishRow?["stringUnit"] as? [String: Any]
            result[key] = unit?["value"] as? String ?? ""
        }
        return result
    }()

    /// Catalog keys grouped by their identifier, the part before the first space.
    static let keysByStem: [String: [String]] = Dictionary(grouping: english.keys, by: stem)

    /// The identifier part of a key or of a lookup result.
    static func stem(_ value: String) -> String {
        String(value.split(separator: " ", maxSplits: 1).first ?? "")
    }
}

/// Asserts that `value`, the result of a `String(localized:)` lookup made in the
/// test runner, names a dotted key that the catalog has, with an English value.
func assertCatalogKey(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
    let stem = StringCatalog.stem(value)
    XCTAssertTrue(stem.contains("."), "\"\(value)\" is not a localized key lookup", file: file, line: line)
    guard let keys = StringCatalog.keysByStem[stem] else {
        XCTFail("\"\(stem)\" is not a key in Localizable.xcstrings", file: file, line: line)
        return
    }
    XCTAssertTrue(
        keys.contains { StringCatalog.english[$0]?.isEmpty == false },
        "\"\(stem)\" has no English value in Localizable.xcstrings",
        file: file,
        line: line
    )
}

final class StringCatalogTestSupportTests: XCTestCase {
    func testTheCatalogIsFound() {
        XCTAssertGreaterThan(StringCatalog.english.count, 500, StringCatalog.url.path)
    }

    func testALookupInTheTestRunnerReturnsItsKey() {
        // The premise of assertCatalogKey: without the app's catalog, a lookup
        // returns its key, with arguments substituted.
        XCTAssertEqual(String(localized: "audio.status.ok"), "audio.status.ok")
        let count = 3
        XCTAssertEqual(String(localized: "premise.notAKey \(count)"), "premise.notAKey 3")
        assertCatalogKey(String(localized: "audio.status.ok"))
    }
}
