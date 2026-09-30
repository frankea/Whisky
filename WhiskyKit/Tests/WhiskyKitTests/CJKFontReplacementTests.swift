//
//  CJKFontReplacementTests.swift
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

/// Covers the decision behind ``Wine/syncCJKFontReplacements(bottle:)``.
/// The `reg import` itself spawns wineserver and is deliberately not
/// exercised, same policy as the audio registry sync.
@Suite("CJK Font Replacement Tests")
struct CJKFontReplacementTests {
    private static let aliases = ["Noto Sans CJK SC", "Noto Sans CJK TC", "Noto Sans CJK JP", "Noto Sans CJK KR"]

    /// The Replacements key as Wine saves it after `cjkfonts`: the fake verbs'
    /// Microsoft aliases, non-ASCII names escaped, and neighbouring keys on
    /// either side, including a subkey.
    private static func userReg(extra: String = "") -> String {
        #"""
        WINE REGISTRY Version 2
        ;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

        #arch=win64

        [Software\\Wine\\Fonts] 1788028146
        #time=1dd37e4465d6628
        "LogPixels"=dword:00000060

        [Software\\Wine\\Fonts\\Replacements] 1788028200
        #time=1dd37e4465d9a10
        @="ignored default value"
        "Batang"="Source Han Sans K"
        "Meiryo"="Source Han Sans"
        "Microsoft JhengHei"="Source Han Sans TC"
        "Microsoft YaHei"="Source Han Sans SC"
        "SimSun"="Source Han Sans SC"
        "\x30e1\x30a4\x30ea\x30aa"="Source Han Sans"

        """# + extra + #"""

        [Software\\Wine\\Fonts\\Replacements\\Unrelated] 1788028200
        "Noto Sans CJK TC"="Subkey, not the key"

        [Software\\Wine\\WineDbg] 1788028146
        "Noto Sans CJK KR"="Another key entirely"
        """#
    }

    private func makeBottle(collection: Bool, userReg: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cjk-fonts-\(UUID().uuidString)")
        let fonts = url.appending(path: "drive_c/windows/Fonts")
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        if collection {
            try Data().write(to: fonts.appending(path: CJKFontReplacements.collectionFile))
        }
        if let userReg {
            try userReg.write(to: url.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        }
        return url
    }

    // MARK: - Table

    @Test("Aliases exactly the families Wine's DirectWrite fallback asks for")
    func aliasesTheFallbackFamilies() {
        #expect(CJKFontReplacements.replacements.map(\.alias) == Self.aliases)
    }

    @Test("Points each alias at the face winetricks registers for that script")
    func pointsAtTheRegisteredFaces() {
        let fonts = Dictionary(
            uniqueKeysWithValues: CJKFontReplacements.replacements.map { ($0.alias, $0.font) }
        )
        #expect(fonts["Noto Sans CJK SC"] == "Source Han Sans SC")
        #expect(fonts["Noto Sans CJK TC"] == "Source Han Sans TC")
        // The collection's Japanese face has no region suffix, and its Korean one is "K", not "KR".
        #expect(fonts["Noto Sans CJK JP"] == "Source Han Sans")
        #expect(fonts["Noto Sans CJK KR"] == "Source Han Sans K")
    }

    @Test("Uses the file winetricks' sourcehansans verb installs")
    func watchesTheWinetricksFile() {
        #expect(CJKFontReplacements.collectionFile == "sourcehansans.ttc")
        #expect(CJKFontReplacements.registryKey == #"HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements"#)
    }

    // MARK: - Decision

    @Test("Adds nothing without Source Han Sans to point at")
    func nothingWithoutTheCollection() {
        #expect(CJKFontReplacements.missing(collectionInstalled: false, existingNames: []).isEmpty)
    }

    @Test("Adds every alias when none is set")
    func everyAliasWhenNoneIsSet() {
        let missing = CJKFontReplacements.missing(collectionInstalled: true, existingNames: [])
        #expect(missing == CJKFontReplacements.replacements)
    }

    @Test("The fake verbs' Microsoft aliases do not stand in for the Noto ones")
    func microsoftAliasesDoNotCount() {
        let existing: Set = ["SimSun", "Microsoft YaHei", "MingLiU", "MS Gothic", "Meiryo", "Gulim", "Batang"]
        let missing = CJKFontReplacements.missing(collectionInstalled: true, existingNames: existing)
        #expect(missing.map(\.alias) == Self.aliases)
    }

    @Test("Never overwrites a value that is already set")
    func leavesExistingValuesAlone() {
        let missing = CJKFontReplacements.missing(collectionInstalled: true, existingNames: ["Noto Sans CJK SC"])
        #expect(missing.map(\.alias) == ["Noto Sans CJK TC", "Noto Sans CJK JP", "Noto Sans CJK KR"])
    }

    @Test("Matches existing names case-insensitively, as the registry does")
    func matchesNamesCaseInsensitively() {
        let missing = CJKFontReplacements.missing(
            collectionInstalled: true, existingNames: ["noto sans cjk tc", "NOTO SANS CJK KR"]
        )
        #expect(missing.map(\.alias) == ["Noto Sans CJK SC", "Noto Sans CJK JP"])
    }

    @Test("Adds nothing once every alias is set")
    func nothingOnceAllAreSet() {
        let missing = CJKFontReplacements.missing(collectionInstalled: true, existingNames: Set(Self.aliases))
        #expect(missing.isEmpty)
    }

    // MARK: - Reading the prefix

    @Test("A prefix after cjkfonts needs all four aliases")
    func cjkfontsPrefixNeedsAllFour() throws {
        let bottle = try makeBottle(collection: true, userReg: Self.userReg())
        defer { try? FileManager.default.removeItem(at: bottle) }

        #expect(CJKFontReplacements.pending(bottleURL: bottle) == CJKFontReplacements.replacements)
    }

    @Test("An alias the user set is left out, whatever it points at")
    func userAliasIsLeftOut() throws {
        let userReg = Self.userReg(extra: #""Noto Sans CJK SC"="Microsoft YaHei""#)
        let bottle = try makeBottle(collection: true, userReg: userReg)
        defer { try? FileManager.default.removeItem(at: bottle) }

        let pending = CJKFontReplacements.pending(bottleURL: bottle)
        #expect(pending.map(\.alias) == ["Noto Sans CJK TC", "Noto Sans CJK JP", "Noto Sans CJK KR"])
    }

    @Test("A prefix without the collection needs nothing")
    func noCollectionNeedsNothing() throws {
        let bottle = try makeBottle(collection: false, userReg: Self.userReg())
        defer { try? FileManager.default.removeItem(at: bottle) }

        #expect(CJKFontReplacements.pending(bottleURL: bottle).isEmpty)
    }

    @Test("A missing Replacements key means every alias is needed")
    func missingKeyNeedsAllFour() throws {
        // `sourcehansans` on its own installs the fonts without writing any alias.
        let bottle = try makeBottle(collection: true, userReg: "WINE REGISTRY Version 2\n")
        defer { try? FileManager.default.removeItem(at: bottle) }

        #expect(CJKFontReplacements.pending(bottleURL: bottle) == CJKFontReplacements.replacements)
    }

    @Test("Adds nothing when user.reg cannot be read")
    func unreadableRegistryAddsNothing() throws {
        let bottle = try makeBottle(collection: true, userReg: nil)
        defer { try? FileManager.default.removeItem(at: bottle) }

        #expect(CJKFontReplacements.pending(bottleURL: bottle).isEmpty)
    }

    // MARK: - Registry document

    @Test("The document adds values without clearing the key")
    func documentAddsWithoutClearing() {
        let document = CJKFontReplacements.registryDocument(for: CJKFontReplacements.replacements)
        let lines = document.components(separatedBy: "\r\n")

        #expect(lines.first == "Windows Registry Editor Version 5.00")
        #expect(lines.contains(#"[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]"#))
        #expect(lines.contains(#""Noto Sans CJK SC"="Source Han Sans SC""#))
        #expect(lines.contains(#""Noto Sans CJK TC"="Source Han Sans TC""#))
        #expect(lines.contains(#""Noto Sans CJK JP"="Source Han Sans""#))
        #expect(lines.contains(#""Noto Sans CJK KR"="Source Han Sans K""#))
        // `[-Key]` would delete the fake verbs' aliases along with any the user set.
        #expect(!document.contains("[-"))
    }

    @Test("The document holds only the aliases it is given")
    func documentHoldsOnlyWhatIsGiven() {
        let only = CJKFontReplacements.replacements.filter { $0.alias == "Noto Sans CJK TC" }
        let document = CJKFontReplacements.registryDocument(for: only)
        let values = document.components(separatedBy: "\r\n").filter { $0.hasPrefix("\"") }

        #expect(values == [#""Noto Sans CJK TC"="Source Han Sans TC""#])
    }
}
