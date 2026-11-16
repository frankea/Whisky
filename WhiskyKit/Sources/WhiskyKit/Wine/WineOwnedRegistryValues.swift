//
//  WineOwnedRegistryValues.swift
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

/// What one launch does with a value Whisky writes into a key of settings
/// (``Wine/DLLOverrideScope/ownedValueNames``), such as wined3d's `renderer`
/// for Rockstar's `Launcher.exe`.
///
/// Such a value is Whisky's only while Whisky put it there. A DLL override
/// Whisky did not write is left alone because its name is not managed; a
/// setting has no such name to go by, so ownership is decided by comparing
/// what the registry holds with what the record says Whisky wrote.
struct OwnedRegistryValueEdit: Equatable {
    /// What the `.reg` document does with the value.
    enum Line: Equatable {
        /// `"name"="data"`.
        case set(String)
        /// `"name"=-`.
        case remove
    }

    /// The full registry key, as ``Wine/DLLOverrideScope/registryKey`` spells it.
    let key: String
    /// The value's name.
    let name: String
    /// The document's line for it; `nil` leaves the value as it is.
    let line: Line?
    /// What Whisky owns of it once the document is imported: the data it
    /// wrote, recorded for the next launch, or `nil`.
    let owned: String?
}

extension Wine.DLLOverrideScope {
    /// The values Whisky may write into a key of settings, each only while
    /// the user has not set it (``Wine/ownedValueEdits(for:record:current:)``);
    /// `nil` for a `DllOverrides` key, whose names are DLLs.
    var ownedValueNames: [String]? {
        switch self {
        case .bottle, .program: nil
        case .direct3D: ["renderer"]
        }
    }
}

extension Wine {
    /// Reads a value's data from a bottle's registry: `nil` when it is not set.
    typealias RegistryValueReader = @MainActor (_ key: String, _ name: String) -> String?

    /// What to do with one owned value.
    ///
    /// A value set to anything other than what Whisky recorded writing is the
    /// user's (winecfg, `regedit`, a guide followed by hand): it is neither
    /// written over nor recorded, so no later launch removes it either. Only
    /// a value Whisky recorded, still holding what it wrote, is taken back
    /// once no longer wanted. One the user deleted is written again while a
    /// launch still wants it, and otherwise forgotten, with nothing removed.
    ///
    /// - Parameters:
    ///   - key: The registry key.
    ///   - name: The value's name.
    ///   - wanted: What the launch wants it to hold; `nil` when nothing.
    ///   - recorded: What the record says Whisky wrote there; `nil` when nothing.
    ///   - current: What the registry holds now; `nil` when the value is not set.
    static func ownedValueEdit(
        key: String, name: String, wanted: String?, recorded: String?, current: String?
    ) -> OwnedRegistryValueEdit {
        if let current, current.lowercased() != recorded?.lowercased() {
            return OwnedRegistryValueEdit(key: key, name: name, line: nil, owned: nil)
        }
        if let wanted {
            return OwnedRegistryValueEdit(key: key, name: name, line: .set(wanted), owned: wanted)
        }
        let takeBack = recorded != nil && current != nil
        return OwnedRegistryValueEdit(key: key, name: name, line: takeBack ? .remove : nil, owned: nil)
    }

    /// The edits for every key of settings among `scopes`.
    ///
    /// Each such scope's string names the values it wants in
    /// `WINEDLLOVERRIDES` syntax (`renderer=gl`); an empty string, or one
    /// leaving a value out, wants none. Only the scope's own
    /// ``DLLOverrideScope/ownedValueNames`` are read from it.
    ///
    /// - Parameters:
    ///   - scopes: A launch's scopes; `DllOverrides` keys are skipped.
    ///   - record: What earlier launches wrote.
    ///   - current: Reads what the registry holds now.
    @MainActor
    static func ownedValueEdits(
        for scopes: [(scope: DLLOverrideScope, overrides: String)],
        record: DLLOverrideRecord,
        current: RegistryValueReader
    ) -> [OwnedRegistryValueEdit] {
        scopes.flatMap { entry -> [OwnedRegistryValueEdit] in
            guard let names = entry.scope.ownedValueNames else { return [] }
            let key = entry.scope.registryKey
            let wanted = parseDLLOverrides(entry.overrides)
            return names.map { name in
                let data = wanted[name].flatMap { !$0.isEmpty && isRenderable(dll: name, mode: $0) ? $0 : nil }
                return ownedValueEdit(
                    key: key, name: name, wanted: data,
                    recorded: record.ownedValue(name, in: key), current: current(key, name)
                )
            }
        }
    }

    /// The `.reg` sections for `edits`, one per key with a line to write. A
    /// key whose values are all left alone gets no section, so the import
    /// does not create it.
    static func ownedValueSections(_ edits: [OwnedRegistryValueEdit]) -> [String] {
        var keys: [String] = []
        var lines: [String: [String]] = [:]
        for edit in edits {
            guard let line = edit.line else { continue }
            if lines[edit.key] == nil {
                keys.append(edit.key)
            }
            switch line {
            case let .set(data):
                lines[edit.key, default: []].append("\"\(edit.name)\"=\"\(data)\"")
            case .remove:
                lines[edit.key, default: []].append("\"\(edit.name)\"=-")
            }
        }
        return keys.flatMap { ["[\($0)]"] + (lines[$0] ?? []) + [""] }
    }

    /// A string value's data in a bottle's registry, read from its `.reg`
    /// file, with the name compared without case as Wine does; `nil` when it
    /// is not set or the hive cannot be read.
    static func registryValue(bottleURL: URL, key: String, name: String) -> String? {
        guard let values = WineRegistryFile.rawValues(bottleURL: bottleURL, key: key),
              let raw = values.first(where: { $0.key.lowercased() == name.lowercased() })?.value
        else { return nil }
        guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else { return raw }
        return String(raw.dropFirst().dropLast())
    }
}

extension DLLOverrideRecord {
    /// What the record says Whisky wrote to `name` in `key`.
    func ownedValue(_ name: String, in key: String) -> String? {
        values[key.lowercased()]?[name.lowercased()]
    }

    /// The record once `edits` have been imported: each value holds what
    /// Whisky owns of it afterwards, and every other value is kept.
    func updated(with edits: [OwnedRegistryValueEdit]) -> DLLOverrideRecord {
        var record = self
        for edit in edits {
            let key = edit.key.lowercased()
            var owned = record.values[key] ?? [:]
            owned[edit.name.lowercased()] = edit.owned
            record.values[key] = owned.isEmpty ? nil : owned
        }
        return record
    }
}
