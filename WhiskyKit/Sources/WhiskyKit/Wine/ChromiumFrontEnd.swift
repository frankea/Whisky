//
//  ChromiumFrontEnd.swift
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

/// A program whose own window is drawn by Chromium, which stays black on
/// D3DMetal and DXMT, while the programs it starts are games that should keep
/// them (#372).
///
/// Recommended runs the listed executables on DXVK, one at a time, through
/// their own `AppDefaults` entries. The table is short and hand-verified:
/// `AppDefaults` is keyed on the file name alone, so only distinctive names
/// belong here, and a row is added only once its layout was checked on a real
/// install (``verifiedIn``).
///
/// An app goes into ``LauncherType`` instead when it needs anything more than
/// a per-executable DXVK pin: environment, locale, chain executables, launcher
/// diagnostics, or the bottle's detected launcher.
public struct ChromiumFrontEnd: Sendable, Equatable, Identifiable {
    /// Where a front end's executable sits in a bottle, checked ahead of time
    /// with a single `fileExists` each, so its entry exists before something
    /// other than Whisky starts it.
    public enum InstallLocation: Sendable, Equatable {
        /// `steamapps/common/<folder>/<relativePath>` in each of the bottle's Steam libraries.
        case steam(folder: String, relativePath: String)
        /// `<relativePath>` under `drive_c/Program Files` or `drive_c/Program Files (x86)`.
        case programFiles(relativePath: String)
    }

    /// A stable identifier for the row.
    public let id: String
    /// The product's name, as shown in the UI. Not localized.
    public let displayName: String
    /// The executables whose window Chromium draws. Same-executable Chromium
    /// children (its GPU process, say) share the entry.
    public let executables: [String]
    /// Separate helper executables that share the front end's set, with the
    /// NVIDIA bridges disabled as a launcher's helpers have them.
    public let helperExecutables: [String]
    /// Where the front end is installed, for the entry written ahead of time.
    public let installLocations: [InstallLocation]
    /// The front end's Steam App ID, when it is sold on Steam.
    public let steamAppId: Int?
    /// The issue or pull request where the row's layout was verified.
    public let verifiedIn: String

    /// 3DMark: its menu is CEF and stays black on D3DMetal, while its
    /// benchmarks (Time Spy, Steel Nomad, the DLSS feature test) are D3D11 and
    /// D3D12 workloads that keep D3DMetal. Its Chromium GPU process runs as
    /// `3DMark.exe` itself, so the row lists no helper.
    public static let threeDMark = ChromiumFrontEnd(
        id: "3dmark",
        displayName: "3DMark",
        executables: ["3DMark.exe"],
        helperExecutables: [],
        installLocations: [
            .steam(folder: "3DMark", relativePath: "bin/x64/3DMark.exe"),
            // The standalone installer's default folder.
            .programFiles(relativePath: "UL/3DMark/3DMark.exe"),
            .programFiles(relativePath: "UL/3DMark/bin/x64/3DMark.exe")
        ],
        steamAppId: 223_850,
        verifiedIn: "#372"
    )

    /// Every front end Recommended steers to DXVK.
    public static let all: [ChromiumFrontEnd] = [.threeDMark]

    /// The front end an executable name belongs to, compared without case as
    /// Wine compares `AppDefaults` keys. Reads nothing from disk.
    public static func match(executableName: String) -> ChromiumFrontEnd? {
        let name = executableName.lowercased()
        guard !name.isEmpty else { return nil }
        return all.first { row in row.executables.contains { $0.lowercased() == name } }
    }

    /// The front end an executable belongs to, by its file name alone. A
    /// Windows-style path counts its last backslash-separated component.
    public static func match(url: URL) -> ChromiumFrontEnd? {
        let name = url.lastPathComponent.split(separator: "\\").last.map(String.init) ?? url.lastPathComponent
        return match(executableName: name)
    }

    /// Whether `libcef.dll` sits beside an executable: the program ships CEF,
    /// and its window may stay black off DXVK. One `fileExists`. Never used
    /// to steer anything: a game can ship CEF for an overlay, and DXVK has no
    /// D3D12 on macOS. It only feeds a suggestion and the diagnostics export.
    public static func shipsCEF(beside url: URL) -> Bool {
        let library = url.deletingLastPathComponent().appending(path: "libcef.dll")
        return FileManager.default.fileExists(atPath: library.path(percentEncoded: false))
    }

    /// This front end's executables that exist in the bottle at one of its
    /// ``installLocations``. Never lists a folder.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle to look in.
    ///   - steamLibraries: The bottle's Steam library roots, if it has Steam.
    func installedExecutables(bottleURL: URL, steamLibraries: [URL]) -> [URL] {
        let driveC = bottleURL.appending(path: "drive_c")
        let candidates = installLocations.flatMap { location -> [URL] in
            switch location {
            case let .steam(folder, relativePath):
                steamLibraries.map {
                    $0.appending(path: "steamapps/common").appending(path: folder).appending(path: relativePath)
                }
            case let .programFiles(relativePath):
                ["Program Files", "Program Files (x86)"].map {
                    driveC.appending(path: $0).appending(path: relativePath)
                }
            }
        }
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }
}
