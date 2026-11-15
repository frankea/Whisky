//
//  KoreanFontFallbackTests.swift
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

/// Covers the Apple SD Gothic Neo fallback ``CJKFontReplacements`` adds for
/// Korean names while a prefix has no Source Han Sans, and the registry file
/// reading it relies on. The `reg import` itself is not exercised.
@Suite("Korean Font Fallback Tests")
struct KoreanFontFallbackTests {
    /// 굴림 (Gulim) as Wine saves the name in `user.reg`.
    private static let escapedGulim = #"\xad74\xb9bc"#

    /// A Replacements key holding a user's own Korean alias, saved with its
    /// name escaped, plus a non-string value and a neighbouring key.
    private static func userReg(extra: String = "") -> String {
        #"""
        WINE REGISTRY Version 2

        [Software\\Wine\\Fonts\\Replacements] 1788028200
        #time=1dd37e4465d9a10
        "Dotum"="Nanum Gothic"
        "LogPixels"=dword:00000060
        "\#(escapedGulim)"="Nanum Gothic"

        """# + extra + #"""

        [Software\\Wine\\WineDbg] 1788028146
        "Batang"="Another key entirely"
        """#
    }

    private func makeBottle(collection: Bool, userReg: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "korean-fonts-\(UUID().uuidString)")
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

    @Test("Points every Korean name, and DirectWrite's Hangul fallback, at Apple SD Gothic Neo")
    func pointsAtAppleSDGothicNeo() {
        let replacements = KoreanFontFallback.replacements
        #expect(replacements.first?.alias == "Noto Sans CJK KR")
        #expect(replacements.allSatisfy { $0.font == "Apple SD Gothic Neo" })
        for name in ["Malgun Gothic", "맑은 고딕", "Gulim", "굴림", "Dotum", "Batang", "Gungsuh"] {
            #expect(replacements.contains { $0.alias == name }, "\(name)")
        }
        #expect(Set(replacements.map(\.alias)).count == replacements.count)
    }

    @Test("Uses the font every Mac ships")
    func usesTheSystemFont() {
        #expect(KoreanFontFallback.hostFontPath == "/System/Library/Fonts/AppleSDGothicNeo.ttc")
    }

    // MARK: - Decision

    @Test("Without Source Han Sans, every Korean name gets the fallback")
    func everyNameWithoutTheCollection() {
        let missing = CJKFontReplacements.missing(
            collectionInstalled: false, koreanFallbackInstalled: true, existingNames: []
        )
        #expect(missing == KoreanFontFallback.replacements)
    }

    @Test("With Source Han Sans, the fallback is never used")
    func collectionWins() {
        let missing = CJKFontReplacements.missing(
            collectionInstalled: true, koreanFallbackInstalled: true, existingNames: []
        )
        #expect(missing == CJKFontReplacements.replacements)
    }

    @Test("A Mac without the font gets nothing")
    func nothingWithoutTheHostFont() {
        let missing = CJKFontReplacements.missing(
            collectionInstalled: false, koreanFallbackInstalled: false, existingNames: []
        )
        #expect(missing.isEmpty)
    }

    @Test("Names already set, in English or escaped Korean, are left alone")
    func leavesSetNamesAlone() {
        let missing = CJKFontReplacements.missing(
            collectionInstalled: false, koreanFallbackInstalled: true,
            existingNames: ["noto sans cjk kr", "Malgun Gothic", Self.escapedGulim]
        )
        let aliases = missing.map(\.alias)
        #expect(!aliases.contains("Noto Sans CJK KR"))
        #expect(!aliases.contains("Malgun Gothic"))
        #expect(!aliases.contains("굴림"))
        #expect(aliases.contains("맑은 고딕"))
        #expect(aliases.count == KoreanFontFallback.replacements.count - 3)
    }

    // MARK: - Reading the prefix

    @Test("A prefix without Source Han Sans gets the fallback for every name it has not set")
    func prefixWithoutTheCollection() throws {
        let bottle = try makeBottle(collection: false, userReg: Self.userReg())
        defer { try? FileManager.default.removeItem(at: bottle) }

        let pending = CJKFontReplacements.pending(bottleURL: bottle, koreanFallbackInstalled: true)
        let expected = KoreanFontFallback.replacements.filter { !["Dotum", "굴림"].contains($0.alias) }
        #expect(pending == expected)
    }

    @Test("Adds nothing when user.reg cannot be read")
    func unreadableRegistryAddsNothing() throws {
        let bottle = try makeBottle(collection: false, userReg: nil)
        defer { try? FileManager.default.removeItem(at: bottle) }

        #expect(CJKFontReplacements.pending(bottleURL: bottle, koreanFallbackInstalled: true).isEmpty)
    }

    @Test("Once Source Han Sans arrives, the Noto alias moves off the fallback")
    func notoAliasMovesToSourceHanSans() throws {
        let fallback = KoreanFontFallback.replacements.map { "\"\($0.alias)\"=\"\($0.font)\"" }
        let others = #""Noto Sans CJK SC"="Source Han Sans SC""# + "\n"
            + #""Noto Sans CJK TC"="Source Han Sans TC""# + "\n"
            + #""Noto Sans CJK JP"="Source Han Sans""#
        let userReg = Self.userReg(extra: fallback.joined(separator: "\n") + "\n" + others)
        let bottle = try makeBottle(collection: true, userReg: userReg)
        defer { try? FileManager.default.removeItem(at: bottle) }

        let pending = CJKFontReplacements.pending(bottleURL: bottle, koreanFallbackInstalled: true)
        #expect(pending == [FontReplacement(alias: "Noto Sans CJK KR", font: "Source Han Sans K")])
    }

    @Test("A Noto alias the user pointed elsewhere stays put when Source Han Sans arrives")
    func userNotoAliasStays() throws {
        let userReg = Self.userReg(extra: #""Noto Sans CJK KR"="Nanum Gothic""#)
        let bottle = try makeBottle(collection: true, userReg: userReg)
        defer { try? FileManager.default.removeItem(at: bottle) }

        let pending = CJKFontReplacements.pending(bottleURL: bottle, koreanFallbackInstalled: true)
        #expect(!pending.contains { $0.alias == "Noto Sans CJK KR" })
    }

    // MARK: - Registry file

    @Test("Raw values come back by name, strings in their quotes")
    func rawValuesByName() throws {
        let bottle = try makeBottle(collection: false, userReg: Self.userReg())
        defer { try? FileManager.default.removeItem(at: bottle) }

        let values = try #require(
            WineRegistryFile.rawValues(bottleURL: bottle, key: CJKFontReplacements.registryKey)
        )
        #expect(values == [
            "Dotum": #""Nanum Gothic""#,
            "LogPixels": "dword:00000060",
            Self.escapedGulim: #""Nanum Gothic""#
        ])
    }

    @Test("Names are spelled the way Wine saves them")
    func savedSpelling() {
        #expect(WineRegistryFile.savedSpelling(of: "Malgun Gothic") == "Malgun Gothic")
        #expect(WineRegistryFile.savedSpelling(of: "굴림") == Self.escapedGulim)
        #expect(WineRegistryFile.savedSpelling(of: "メイリオ") == #"\x30e1\x30a4\x30ea\x30aa"#)
        // Padded only when a hex digit follows, so the escape cannot swallow it.
        #expect(WineRegistryFile.savedSpelling(of: "é1") == #"\x00e91"#)
        #expect(WineRegistryFile.savedSpelling(of: "éz") == #"\xe9z"#)
        #expect(WineRegistryFile.savedSpelling(of: #"a"b\c"#) == #"a\"b\\c"#)
    }

    // MARK: - Sync

    @Test("A sync imports the fallback into a prefix without Source Han Sans")
    @MainActor
    func syncImportsTheFallback() async throws {
        let bottle = try Bottle(bottleUrl: makeBottle(collection: false, userReg: Self.userReg()))
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        var documents: [String] = []

        await Wine.syncCJKFontReplacements(bottle: bottle, koreanFallbackInstalled: true) { document, _ in
            documents.append(document)
        }

        let expected = KoreanFontFallback.replacements.filter { !["Dotum", "굴림"].contains($0.alias) }
        #expect(documents == [CJKFontReplacements.registryDocument(for: expected)])
        #expect(documents.first?.contains(#""맑은 고딕"="Apple SD Gothic Neo""#) == true)
        #expect(documents.first?.contains("[-") == false)
    }
}
