//
//  WineRegistryFileTests.swift
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
import Testing
@testable import WhiskyKit

@Suite("Wine Registry File Tests")
struct WineRegistryFileTests {
    private static let replacementsKey = #"HKCU\Software\Wine\Fonts\Replacements"#

    /// A `user.reg` as Wine saves it: timestamped headers, `#time` lines, a
    /// default value, an escaped non-ASCII name, and neighbouring keys on
    /// either side, including a subkey.
    private static let userReg = #"""
    WINE REGISTRY Version 2
    ;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

    #arch=win64

    [Software\\Wine\\Fonts] 1788028146
    #time=1dd37e4465d6628
    "LogPixels"=dword:00000060
    "SimSun"="Not the key"

    [Software\\Wine\\Fonts\\Replacements] 1788028200
    #time=1dd37e4465d9a10
    @="ignored default value"
    "Meiryo"="Source Han Sans"
    "SimSun"="Source Han Sans SC"
    "\x30e1\x30a4\x30ea\x30aa"="Source Han Sans"

    [Software\\Wine\\Fonts\\Replacements\\Unrelated] 1788028200
    "Gulim"="Subkey, not the key"

    [Software\\Wine\\WineDbg] 1788028146
    "Batang"="Another key entirely"
    """#

    private func makePrefix(userReg: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "registry-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let userReg {
            try userReg.write(to: url.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        }
        return url
    }

    // MARK: - valueNames

    @Test("Lists the names set directly under the key, as the file spells them")
    func listsNamesUnderTheKey() throws {
        let prefix = try makePrefix(userReg: Self.userReg)
        defer { try? FileManager.default.removeItem(at: prefix) }

        let names = WineRegistryFile.valueNames(bottleURL: prefix, key: Self.replacementsKey)
        #expect(names == ["Meiryo", "SimSun", #"\x30e1\x30a4\x30ea\x30aa"#])
    }

    @Test("Accepts the long hive name as well as the short one")
    func acceptsTheLongHiveName() throws {
        let prefix = try makePrefix(userReg: Self.userReg)
        defer { try? FileManager.default.removeItem(at: prefix) }

        let long = #"HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements"#
        #expect(WineRegistryFile.valueNames(bottleURL: prefix, key: long)?.count == 3)
    }

    @Test("An escaped quote does not end a name")
    func escapedQuoteDoesNotEndAName() throws {
        let userReg = "[Software\\\\Test] 1\n\"say \\\"hi\\\"\"=\"x\"\n\"back\\\\slash\"=\"y\"\n"
        let prefix = try makePrefix(userReg: userReg)
        defer { try? FileManager.default.removeItem(at: prefix) }

        let names = WineRegistryFile.valueNames(bottleURL: prefix, key: #"HKCU\Software\Test"#)
        #expect(names == [#"say \"hi\""#, #"back\\slash"#])
    }

    @Test("A missing key reads as no names, a missing file as unknown")
    func missingKeyVersusMissingFile() throws {
        let prefix = try makePrefix(userReg: Self.userReg)
        defer { try? FileManager.default.removeItem(at: prefix) }

        #expect(WineRegistryFile.valueNames(bottleURL: prefix, key: #"HKCU\Software\Absent"#) == [])
        // No system.reg in this prefix.
        #expect(WineRegistryFile.valueNames(bottleURL: prefix, key: #"HKLM\Software\Absent"#) == nil)
    }

    // MARK: - readValue

    @Test("Reads a value from the key it names, not a neighbour's")
    func readsFromTheNamedKey() throws {
        let prefix = try makePrefix(userReg: Self.userReg)
        defer { try? FileManager.default.removeItem(at: prefix) }

        #expect(
            WineRegistryFile.readValue(bottleURL: prefix, key: Self.replacementsKey, valueName: "SimSun")
                == "Source Han Sans SC"
        )
        #expect(
            WineRegistryFile.readValue(bottleURL: prefix, key: #"HKCU\Software\Wine\Fonts"#, valueName: "LogPixels")
                == "dword:00000060"
        )
        #expect(WineRegistryFile.readValue(bottleURL: prefix, key: Self.replacementsKey, valueName: "Gulim") == nil)
    }

    @Test("Reads nothing for a hive it does not know")
    func unknownHiveReadsNothing() throws {
        let prefix = try makePrefix(userReg: Self.userReg)
        defer { try? FileManager.default.removeItem(at: prefix) }

        #expect(WineRegistryFile.readValue(bottleURL: prefix, key: #"HKCR\.txt"#, valueName: "") == nil)
        #expect(WineRegistryFile.valueNames(bottleURL: prefix, key: #"HKCR\.txt"#) == nil)
    }
}
