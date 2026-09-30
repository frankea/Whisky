//
//  WineFontReplacements.swift
//  WhiskyKit
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
import os.log

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineFontReplacements")

/// A font family name that Wine resolves to another, installed family.
struct FontReplacement: Equatable, Sendable {
    /// The family that is asked for.
    let alias: String
    /// The installed family that stands in for it.
    let font: String
}

/// The Noto CJK aliases that let Wine's DirectWrite fallback reach the
/// Source Han Sans fonts winetricks installs.
///
/// For CJK text its font lacks, Wine's DirectWrite falls back to Noto Sans
/// CJK SC, TC, JP or KR, by script and locale (the system fallback table in
/// `dlls/dwrite/analyzer.c`). No prefix has those families. The `cjkfonts`
/// verb, through `fakechinese`, `fakejapanese` and `fakekorean`, installs
/// Source Han Sans, the same typeface under Adobe's name, but aliases only
/// the Microsoft families (SimSun, Meiryo, Gulim and the rest). Chromium
/// relies on that fallback, so Steam's UI kept drawing CJK text as boxes
/// with the fonts installed until the Noto names were aliased too.
enum CJKFontReplacements {
    /// Where Wine reads family aliases, for GDI and DirectWrite alike.
    static let registryKey = #"HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements"#

    /// The collection winetricks' `sourcehansans` verb installs, which
    /// `cjkfonts` and the `fake` verbs above all pull in.
    static let collectionFile = "sourcehansans.ttc"

    /// Each family the fallback asks for, and the collection's face for the
    /// same script. The collection names its Japanese face plain "Source Han
    /// Sans" and its Korean one "Source Han Sans K", as winetricks registers
    /// them.
    static let replacements: [FontReplacement] = [
        FontReplacement(alias: "Noto Sans CJK SC", font: "Source Han Sans SC"),
        FontReplacement(alias: "Noto Sans CJK TC", font: "Source Han Sans TC"),
        FontReplacement(alias: "Noto Sans CJK JP", font: "Source Han Sans"),
        FontReplacement(alias: "Noto Sans CJK KR", font: "Source Han Sans K")
    ]

    /// The aliases a prefix still needs.
    ///
    /// Without the collection there is nothing to point an alias at. A name
    /// that is already set is left alone, whatever it holds, so a value the
    /// user chose is never overwritten.
    ///
    /// - Parameters:
    ///   - collectionInstalled: Whether the Source Han Sans collection is in
    ///     the prefix's fonts folder.
    ///   - existingNames: The value names already under ``registryKey``.
    /// - Returns: The aliases to add, in table order.
    static func missing(collectionInstalled: Bool, existingNames: Set<String>) -> [FontReplacement] {
        guard collectionInstalled else {
            return []
        }
        // Registry value names are case-insensitive.
        let taken = Set(existingNames.map { $0.lowercased() })
        return replacements.filter { !taken.contains($0.alias.lowercased()) }
    }

    /// The aliases to add to a bottle, read from its prefix without starting Wine.
    ///
    /// Empty when the collection is missing, when every alias is set, and
    /// when `user.reg` cannot be read, since a value that cannot be seen
    /// cannot be left alone either.
    static func pending(bottleURL: URL) -> [FontReplacement] {
        let collection = bottleURL
            .appending(path: "drive_c/windows/Fonts")
            .appending(path: collectionFile)
        guard FileManager.default.fileExists(atPath: collection.path(percentEncoded: false)),
              let existingNames = WineRegistryFile.valueNames(bottleURL: bottleURL, key: registryKey)
        else {
            return []
        }
        return missing(collectionInstalled: true, existingNames: existingNames)
    }

    /// A `.reg` that adds `replacements` and leaves the key's other values alone.
    static func registryDocument(for replacements: [FontReplacement]) -> String {
        var lines = ["Windows Registry Editor Version 5.00", "", "[\(registryKey)]"]
        lines += replacements.map { "\"\($0.alias)\"=\"\($0.font)\"" }
        lines.append("")
        return lines.joined(separator: "\r\n")
    }
}

extension Wine {
    /// Adds the Noto CJK aliases once winetricks has installed Source Han Sans.
    ///
    /// Runs on every launch, because fonts can arrive at any time and through
    /// either winetricks route. A bottle without the collection costs a file
    /// check, one with it a read of `user.reg`, and a `reg import` of just the
    /// missing values happens only while one is missing. It never fails a
    /// launch.
    ///
    /// - Parameters:
    ///   - bottle: The bottle a program is about to start in.
    ///   - importer: What imports the missing aliases.
    @MainActor
    static func syncCJKFontReplacements(
        bottle: Bottle,
        importer: RegistryImporter = { try await importRegistry(document: $0, bottle: $1) }
    ) async {
        // Off the main actor: the whole hive is read, and it grows with the prefix.
        let bottleURL = bottle.url
        let pending = await Task.detached(priority: .userInitiated) {
            CJKFontReplacements.pending(bottleURL: bottleURL)
        }.value
        guard !pending.isEmpty else {
            return
        }

        do {
            try await importer(CJKFontReplacements.registryDocument(for: pending), bottle)
            logger.info("Added \(pending.count) CJK font aliases to '\(bottle.settings.name)'")
        } catch {
            logger.error(
                "CJK font alias sync failed for '\(bottle.settings.name)': \(error.localizedDescription)"
            )
        }
    }
}
