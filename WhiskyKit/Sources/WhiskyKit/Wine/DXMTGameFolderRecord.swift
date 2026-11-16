//
//  DXMTGameFolderRecord.swift
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

/// What a launch does with the DXMT copies Whisky keeps beside a game's executables.
///
/// A launcher that carries a game's plan, such as `steam.exe -applaunch`, keeps
/// DXVK in `system32`, since its own Chromium processes need it, and one
/// `system32` cannot hold both layers: both ship `d3d11.dll`. A game whose plan
/// is DXMT gets DXMT's trio in its own folder instead, which Wine's loader
/// searches before `system32` for a native DLL (#378).
enum DXMTGameFolderAction: Equatable {
    /// A launcher carries the game's DXMT plan: the trio goes beside each of
    /// the game's executables, and copies already there are kept current.
    case deploy
    /// The game itself starts on DXMT, which `system32` serves: copies already
    /// beside it are kept current, and none are added.
    case refresh
    /// The launch's plan is not DXMT: the copies Whisky placed beside the
    /// game are removed, so they cannot take over from the plan's layer.
    case remove

    /// The action for a launch.
    ///
    /// - Parameters:
    ///   - effectiveBackend: The launch's backend after overrides and `.recommended` resolution.
    ///   - launcherCarriesDescendantPlan: Whether a launcher is started to carry a game's plan.
    init(effectiveBackend: GraphicsBackend, launcherCarriesDescendantPlan: Bool) {
        if effectiveBackend == .dxmt {
            self = launcherCarriesDescendantPlan ? .deploy : .refresh
        } else {
            self = .remove
        }
    }
}

/// The DXMT copies Whisky placed in a bottle's game folders, each with the
/// SHA-256 of what it wrote, so a copy is only ever replaced or removed while
/// it is still exactly what Whisky put there.
struct DXMTGameFolderRecord: Codable, Equatable {
    /// Each copy's path relative to the bottle's `drive_c`, to its lowercase hex SHA-256.
    var copies: [String: String] = [:]

    static func url(in bottleURL: URL) -> URL {
        bottleURL.appending(path: ".dxmt-game-folder-copies.plist")
    }

    /// The bottle's record, or an empty one when there is none or it cannot be read.
    ///
    /// Every copy whose path does not stay inside the bottle's `drive_c` is
    /// dropped here (``DriveCRecordKey/isContained(_:in:)``). The removals
    /// and deploys re-check each folder they touch as well, so this keeps such
    /// a path from reaching any other code that reads the record.
    static func load(from bottleURL: URL) -> DXMTGameFolderRecord {
        guard let data = try? Data(contentsOf: url(in: bottleURL)),
              var record = try? PropertyListDecoder().decode(DXMTGameFolderRecord.self, from: data)
        else { return DXMTGameFolderRecord() }
        let driveC = bottleURL.appending(path: "drive_c")
        record.copies = record.copies.filter { DriveCRecordKey.isContained($0.key, in: driveC) }
        return record
    }

    /// Writes the record, or removes the file once no copy is left.
    func save(to bottleURL: URL) throws {
        let url = Self.url(in: bottleURL)
        guard !copies.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Runs `body` while holding an exclusive lock on the bottle's folder, so
    /// the app and `whisky` cannot interleave their reads and writes of the record.
    ///
    /// Without a lock (the folder cannot be opened), `body` runs anyway: a
    /// lost update only leaves a copy untracked, which the next deploy adopts.
    static func withLock<T>(in bottleURL: URL, _ body: () -> T) -> T {
        let descriptor = open(bottleURL.path(percentEncoded: false), O_RDONLY)
        guard descriptor >= 0 else { return body() }
        defer { close(descriptor) }
        let locked = flock(descriptor, LOCK_EX) == 0
        defer {
            if locked {
                flock(descriptor, LOCK_UN)
            }
        }
        return body()
    }

    /// Whether any copy is recorded in the folder with the given key.
    func hasCopies(inFolder key: String) -> Bool {
        Wine.dxmtGameFolderDLLs.contains { copies[DXMTGameFolder.key(key, $0)] != nil }
    }

    /// The keys of the folders holding recorded copies.
    var folderKeys: Set<String> {
        Set(copies.keys.map(DXMTGameFolder.folderKey(ofCopy:)))
    }
}

/// A folder holding game executables, once it is known to be one Whisky may write into.
struct DXMTGameFolder {
    /// The folder with its symbolic links resolved.
    let url: URL
    /// Its path relative to the bottle's `drive_c`.
    let key: String
    /// The executables the launch named in it.
    var executables: [URL]

    /// The record key of `dll` in the folder with key `folder`.
    static func key(_ folder: String, _ dll: String) -> String {
        folder.isEmpty ? dll : "\(folder)/\(dll)"
    }

    /// The key of the folder a recorded copy is in.
    static func folderKey(ofCopy key: String) -> String {
        var components = key.split(separator: "/", omittingEmptySubsequences: false)
        components.removeLast()
        return components.joined(separator: "/")
    }

    /// The key of the Steam game install a folder belongs to
    /// (`.../steamapps/common/<Game>`), or `nil` outside one.
    static func steamInstallKey(of key: String) -> String? {
        let components = key.split(separator: "/").map(String.init)
        let lowercased = components.map { $0.lowercased() }
        guard let index = lowercased.indices.first(where: { index in
            index + 2 < lowercased.count && lowercased[index] == "steamapps" && lowercased[index + 1] == "common"
        })
        else { return nil }
        return components.prefix(index + 3).joined(separator: "/")
    }

    /// Whether the folder with key `other` belongs to the same game as this
    /// folder, so a launch of this folder's executable also keeps its copies
    /// in step: any folder of the same Steam install, such as an Unreal
    /// game's `Binaries/Win64` beside its root stub, or, outside Steam, a
    /// folder below this one.
    ///
    /// A Steam install is never part of anything above it, so starting
    /// `steam.exe` alone does not reach into its library.
    func belongsToSameGame(_ other: String) -> Bool {
        let otherInstall = Self.steamInstallKey(of: other)?.lowercased()
        if let install = Self.steamInstallKey(of: key) {
            return otherInstall == install.lowercased()
        }
        guard !key.isEmpty, otherInstall == nil else { return false }
        return other.lowercased().hasPrefix(key.lowercased() + "/")
    }

    func key(for dll: String) -> String {
        Self.key(key, dll)
    }
}
