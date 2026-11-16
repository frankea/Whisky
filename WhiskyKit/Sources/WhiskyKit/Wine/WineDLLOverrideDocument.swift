//
//  WineDLLOverrideDocument.swift
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

/// The DLL names a launch wrote into each override key beyond the managed
/// ones: the user's custom overrides, a GameDB variant's, a setup fix's.
///
/// A launch removes a value only when Whisky could have written it, so a
/// value winetricks or winecfg wrote stays. The managed names are known
/// without a record (``Wine/managedDLLNames``); a custom override is not, and
/// once the user deletes it from the settings the name is gone from them too.
/// This record is what lets the next launch take that value back.
///
/// Each launch replaces the record only for the keys it writes, so a launch
/// of one program never forgets what an earlier launch wrote for another. A
/// bottle without a record (one last launched by an older version, whose
/// launches replaced every key wholesale) starts with none, which costs only
/// a custom override removed since that last launch.
struct DLLOverrideRecord: Codable, Equatable {
    /// Lowercased registry key to the lowercased DLL names written there.
    var names: [String: Set<String>] = [:]
    /// Lowercased key of settings to lowercased value name to the data
    /// Whisky wrote there (``OwnedRegistryValueEdit``). A record saved before
    /// these existed has none.
    var values: [String: [String: String]] = [:]

    private enum CodingKeys: String, CodingKey {
        case names
        case values
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        names = try container.decodeIfPresent([String: Set<String>].self, forKey: .names) ?? [:]
        values = try container.decodeIfPresent([String: [String: String]].self, forKey: .values) ?? [:]
    }

    static func url(in bottleURL: URL) -> URL {
        bottleURL.appending(path: ".dll-override-names.plist")
    }

    /// The bottle's record, or an empty one when there is none or it cannot be read.
    static func load(from bottleURL: URL) -> DLLOverrideRecord {
        guard let data = try? Data(contentsOf: url(in: bottleURL)),
              let record = try? PropertyListDecoder().decode(DLLOverrideRecord.self, from: data)
        else { return DLLOverrideRecord() }
        return record
    }

    func save(to bottleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: Self.url(in: bottleURL), options: .atomic)
    }

    /// The names recorded for `key`.
    func names(for key: String) -> Set<String> {
        names[key.lowercased()] ?? []
    }

    /// The record once `scopes` have been written: each of their keys holds
    /// exactly the unmanaged names it was given, and every other key is kept.
    func updated(with scopes: [(key: String, overrides: [String: String])]) -> DLLOverrideRecord {
        var record = self
        for scope in scopes {
            let written = Set(
                scope.overrides
                    .filter { Wine.isRenderable(dll: $0.key, mode: $0.value) }
                    .map { $0.key.lowercased() }
            ).subtracting(Wine.managedDLLNames)
            record.names[scope.key.lowercased()] = written.isEmpty ? nil : written
        }
        return record
    }
}

extension Wine {
    /// The DLL names Whisky writes on its own account: both translation
    /// layer presets, whichever builtin is behind `d3d12`, and the NVIDIA
    /// bridges launcher helpers get disabled.
    ///
    /// A launch removes these from every key it writes unless it sets them,
    /// whether or not a record says it wrote them, so a bottle last launched
    /// by an older version still loses a stale DXVK set when it switches away.
    static let managedDLLNames: Set<String> = {
        let presets = DLLOverrideResolver.dxvkPreset(builtinD3D12IsD3DMetal: true)
            + DLLOverrideResolver.dxmtPreset(builtinD3D12IsD3DMetal: true)
        return Set(presets.map { $0.dllName.lowercased() }).union(["nvapi", "nvapi64", "nvngx"])
    }()

    /// The translation layer names in winetricks' spelling, `*name`, which
    /// every key a launch writes loses.
    ///
    /// Winetricks writes each override with a leading `*` (`winetricks dxvk`
    /// leaves `"*d3d11"="native"`), and Wine reads `*name` whenever a key has no
    /// `name` of its own. A bottle on D3DMetal or wined3d writes no `d3d11` or
    /// `dxgi`, so a starred one would run the game on whatever DXVK left in
    /// `system32` while the backend picker says otherwise. Deleting the key
    /// used to take these too, and the backend picker keeps that authority:
    /// this overrides a winetricks choice on purpose. Its other overrides
    /// (`*d3dx9_43`, `*xaudio2_7`) are not translation layers and stay.
    static let starredBackendDLLNames: Set<String> = {
        let presets = DLLOverrideResolver.dxvkPreset(builtinD3D12IsD3DMetal: true)
            + DLLOverrideResolver.dxmtPreset(builtinD3D12IsD3DMetal: true)
        return Set(presets.map { "*" + $0.dllName.lowercased() })
    }()

    /// Renders a `.reg` giving each key `overrides` and taking back the values
    /// Whisky wrote there before and no longer wants.
    ///
    /// The key is not deleted and recreated: that also took every value
    /// winetricks or winecfg wrote, so a D3DMetal launch, whose bottle key holds
    /// nothing of Whisky's, emptied it. Values are removed one by one instead
    /// (`"name"=-`), and only for names Whisky could have written: the managed
    /// names, and what `record` says an earlier launch wrote into that key.
    /// The one exception is winetricks' starred translation layer names
    /// (``starredBackendDLLNames``), which would otherwise outvote the backend.
    ///
    /// Keys of settings follow in sections of their own, which never get a
    /// managed or starred DLL name removed: only their owned values are
    /// written or taken back (``ownedValueEdits(for:record:current:)``).
    ///
    /// - Parameters:
    ///   - scopes: Each `DllOverrides` key and the overrides it should hold.
    ///   - record: What earlier launches wrote beyond the managed names.
    ///   - ownedValues: What to do with each value Whisky owns in a key of settings.
    static func registryDocument(
        for scopes: [(key: String, overrides: [String: String])],
        record: DLLOverrideRecord = DLLOverrideRecord(),
        ownedValues: [OwnedRegistryValueEdit] = []
    ) -> String {
        var lines = ["Windows Registry Editor Version 5.00", ""]
        for scope in scopes {
            let renderable = scope.overrides
                .filter { isRenderable(dll: $0.key, mode: $0.value) }
                .sorted { $0.key < $1.key }
            let kept = Set(renderable.map { $0.key.lowercased() })
            let removals = managedDLLNames.union(record.names(for: scope.key))
                .subtracting(kept)
                .filter { isRenderable(dll: $0, mode: "") }
                .union(starredBackendDLLNames)
                .sorted()
            lines.append("[\(scope.key)]")
            for dll in removals {
                lines.append("\"\(dll)\"=-")
            }
            for (dll, mode) in renderable {
                lines.append("\"\(dll)\"=\"\(mode)\"")
            }
            lines.append("")
        }
        lines += ownedValueSections(ownedValues)
        return lines.joined(separator: "\r\n")
    }

    /// Whether an override can be rendered without corrupting the document.
    ///
    /// Custom overrides are user-typed, and a quote or backslash in a name would
    /// terminate the value early and take every later scope down with it. A DLL
    /// name is a filename and a mode is a list of known words, so anything
    /// outside these sets could not have loaded regardless; dropping it costs
    /// nothing and contains the blast radius to the one bad entry.
    static func isRenderable(dll: String, mode: String) -> Bool {
        let name = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-+")
        let modes = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz,")
        guard !dll.isEmpty else { return false }
        return dll.lowercased().unicodeScalars.allSatisfy(name.contains)
            && mode.lowercased().unicodeScalars.allSatisfy(modes.contains)
    }
}
