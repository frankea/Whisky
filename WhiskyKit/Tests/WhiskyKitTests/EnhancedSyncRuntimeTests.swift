//
//  EnhancedSyncRuntimeTests.swift
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
import SemanticVersion
import Testing
@testable import WhiskyKit

/// Covers ``WhiskyWineVersion/msyncCapable``, which decides whether the
/// Enhanced Sync pickers say the installed runtime ignores the setting.
@Suite("Enhanced Sync Runtime Tests")
struct EnhancedSyncRuntimeTests {
    /// The version plist Wine Libraries 3.1.1 installs, as shipped.
    private static let stockPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>dxmtVersion</key>
    \t<string>0.80</string>
    \t<key>dxvkVersion</key>
    \t<string>1.10.3</string>
    \t<key>version</key>
    \t<dict>
    \t\t<key>major</key>
    \t\t<integer>3</integer>
    \t\t<key>minor</key>
    \t\t<integer>1</integer>
    \t\t<key>patch</key>
    \t\t<integer>1</integer>
    \t</dict>
    </dict>
    </plist>
    """

    private func info(fromPlist plist: String) throws -> WhiskyWineVersion? {
        let url = FileManager.default.temporaryDirectory.appending(path: "runtime-\(UUID().uuidString).plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return WhiskyWineInstaller.whiskyWineInfo(at: url)
    }

    @Test("The stock 3.1.1 runtime does not implement Enhanced Sync")
    func stockRuntimeIsNotCapable() throws {
        let info = try #require(try info(fromPlist: Self.stockPlist))

        #expect(info.version == SemanticVersion(3, 1, 1))
        #expect(info.msyncCapable == nil)
        #expect(!info.implementsEnhancedSync)
    }

    @Test("A runtime that advertises msyncCapable implements Enhanced Sync")
    func advertisedRuntimeIsCapable() throws {
        let plist = Self.stockPlist.replacingOccurrences(
            of: "\t<key>version</key>", with: "\t<key>msyncCapable</key>\n\t<true/>\n\t<key>version</key>"
        )
        let info = try #require(try info(fromPlist: plist))

        #expect(info.msyncCapable == true)
        #expect(info.implementsEnhancedSync)
    }

    @Test("A runtime that says false does not implement Enhanced Sync")
    func explicitFalseIsNotCapable() {
        #expect(!WhiskyWineVersion(version: SemanticVersion(4, 0, 0), msyncCapable: false).implementsEnhancedSync)
    }

    @Test("msyncCapable survives a round trip, and an absent one stays absent")
    func roundTrip() throws {
        let encoder = PropertyListEncoder()
        let decoder = PropertyListDecoder()

        let capable = WhiskyWineVersion(version: SemanticVersion(4, 0, 0), msyncCapable: true)
        let decoded = try decoder.decode(WhiskyWineVersion.self, from: encoder.encode(capable))
        #expect(decoded.msyncCapable == true)

        let legacy = WhiskyWineVersion(version: SemanticVersion(3, 1, 1))
        let data = try encoder.encode(legacy)
        let keys = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        ).keys
        #expect(!keys.contains("msyncCapable"))
        #expect(try decoder.decode(WhiskyWineVersion.self, from: data).msyncCapable == nil)
    }
}
