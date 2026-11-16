//
//  RockstarD3DLayoutRecord.swift
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

import CryptoKit
import Foundation

/// What Whisky wrote into a bottle for the Rockstar Games Launcher's swapped
/// layout (``RockstarD3DLayout/swapped(source:)``), kept beside the bottle's
/// settings as `.rockstar-d3d-layout.plist`.
///
/// The swap writes files into folders that belong to other programs (Steam's
/// Chromium, Social Club) and puts a file into `system32` that no DXVK launch
/// would. Whisky must be able to take all of it back exactly, after a crash,
/// an engine update, or the user turning the setting off, and never touch a
/// file it did not write. So every file is recorded with the SHA-256 of what
/// was written, before it is written, and the record is finished last:
///
/// - The record existing is what makes a later launch that does not swap tear
///   the layout down. A bottle that never swapped has no record and is never
///   touched.
/// - A copy is removed only while it still hashes to what the record says, or
///   to the current DXVK payload's bytes: either way it is Whisky's DXVK, not
///   a file the program shipped.
/// - The engine stamp and the source's hash tell a launch that the `system32`
///   copy was made from another Wine, so it is made again. The stamp alone
///   misses an engine re-cut under the same version.
struct RockstarD3DLayoutRecord: Codable, Equatable {
    /// The format this build writes. A newer record is not read: it may
    /// describe files in a way this build would take back wrongly.
    static let currentVersion = 1

    /// The record's format.
    var version: Int = currentVersion
    /// The engine the `system32` copy was made for
    /// (`GPTKImporter.runtimeVersionStamp(inLibraryFolder:)`).
    var engineStamp: String
    /// The SHA-256 of Wine's builtin-marked `d3d11.dll` the copy was made from.
    var sourceSHA256: String
    /// The SHA-256 of the stripped copy written to `system32\d3d11.dll`; `nil`
    /// in the record a swap saves before it writes anything, so a crash part
    /// way through leaves a record of every file it may have created.
    var system32D3D11: String?
    /// Each DXVK copy, by its path relative to the bottle's `drive_c` with `/`
    /// between components, to the SHA-256 of what was written, such as
    /// `Program Files (x86)/Steam/bin/cef/cef.win64/d3d11.dll`.
    var copies: [String: String] = [:]
    /// The folders, relative to `drive_c`, that Whisky created to hold copies
    /// (Social Club's before Rockstar installs it, and `Rockstar Games` when
    /// that was missing too), deepest first. They are removed again only while
    /// empty, so one Rockstar's installer filled stays.
    var createdFolders: [String] = []

    /// The record file of the bottle at `bottleURL`.
    static func url(in bottleURL: URL) -> URL {
        bottleURL.appending(path: ".rockstar-d3d-layout.plist")
    }

    /// Whether the bottle has a record file, readable or not.
    static func exists(in bottleURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(in: bottleURL).path(percentEncoded: false))
    }

    /// The bottle's record, or `nil` when there is none, it cannot be read,
    /// or it was written by a newer build.
    ///
    /// A file that exists but cannot be read still counts as a record
    /// (``exists(in:)``) with nothing in it: the next swap adopts copies that
    /// hold the payload's bytes, and a teardown deletes the file and leaves
    /// any file it cannot vouch for where it is.
    ///
    /// The file sits in the bottle, where anyone can edit it or ship it in a
    /// shared bottle, and its paths are what a teardown removes and what the
    /// diagnostics report hashes. So every entry that does not stay inside
    /// the bottle's `drive_c` is dropped here, before any code uses it
    /// (``DriveCRecordKey/isContained(_:in:)``).
    static func load(from bottleURL: URL) -> RockstarD3DLayoutRecord? {
        guard let data = try? Data(contentsOf: url(in: bottleURL)),
              var record = try? PropertyListDecoder().decode(RockstarD3DLayoutRecord.self, from: data),
              record.version <= currentVersion
        else { return nil }
        let driveC = bottleURL.appending(path: "drive_c")
        record.copies = record.copies.filter { DriveCRecordKey.isContained($0.key, in: driveC) }
        record.createdFolders = record.createdFolders.filter { DriveCRecordKey.isContained($0, in: driveC) }
        return record
    }

    /// Writes the record in one step, so a reader never sees half of it.
    func save(to bottleURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: Self.url(in: bottleURL), options: .atomic)
    }

    /// Removes the bottle's record file, if it has one.
    static func remove(from bottleURL: URL) throws {
        guard exists(in: bottleURL) else { return }
        try FileManager.default.removeItem(at: url(in: bottleURL))
    }

    /// The folders holding recorded copies, lowercased, as keys relative to
    /// `drive_c`: the served folders a launch from the Programs tab keeps the
    /// layout for.
    var copyFolderKeys: Set<String> {
        Set(copies.keys.map { DXMTGameFolder.folderKey(ofCopy: $0).lowercased() })
    }

    /// The record key of `dll` in the folder with key `folder`.
    static func key(_ folder: String, _ dll: String) -> String {
        DXMTGameFolder.key(folder, dll)
    }

    /// The lowercase hex SHA-256 of the file at `url`, or `nil` when it
    /// cannot be read.
    static func sha256(of url: URL) -> String? {
        (try? Data(contentsOf: url)).map(sha256)
    }

    /// The lowercase hex SHA-256 of `data`.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
