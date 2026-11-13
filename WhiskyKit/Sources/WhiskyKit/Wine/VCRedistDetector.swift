//
//  VCRedistDetector.swift
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

/// Detects whether the Microsoft Visual C++ 2015-2022 runtime is installed in a prefix.
///
/// Wine ships its own `msvcp140.dll` and `vcruntime140.dll`, and wineboot copies
/// them into every prefix's `system32` and `syswow64`, so the files existing says
/// nothing. Wine marks its copies at offset 0x40, where a native PE carries its
/// DOS stub: "Wine builtin DLL" for builtin modules, "Wine placeholder DLL" for
/// fake ones. The runtime counts as installed when one of those folders holds
/// both DLLs as native PE files, which is what the redistributable (or
/// winetricks' `vcrun2019`) leaves behind.
///
/// The check reads files, so call it off the main thread.
public enum VCRedistDetector {
    /// The DLLs every VC++ 2015-2022 redistributable installs for both architectures.
    static let runtimeDLLs = ["msvcp140.dll", "vcruntime140.dll"]

    /// The prefix folders a redistributable installs into: 64-bit, then 32-bit.
    static let systemFolders = ["system32", "syswow64"]

    /// Wine's markers at offset 0x40 of the DLLs it installs itself.
    static let wineSignatures = [Data("Wine builtin DLL".utf8), Data("Wine placeholder DLL".utf8)]

    /// Whether the VC++ 2015-2022 runtime is installed in a prefix.
    ///
    /// - Parameter prefixURL: The Wine prefix root (the bottle folder holding `drive_c`).
    /// - Returns: `true` when `system32` or `syswow64` holds native copies of
    ///   both runtime DLLs.
    public static func isInstalled(prefixURL: URL) -> Bool {
        let windows = prefixURL.appending(path: "drive_c").appending(path: "windows")
        return systemFolders.contains { folder in
            let directory = windows.appending(path: folder)
            return runtimeDLLs.allSatisfy { isNativePE(directory.appending(path: $0)) }
        }
    }

    /// Whether a file is a PE image that Wine did not install as its own.
    ///
    /// Fails closed: a missing, unreadable, or truncated file, or one without
    /// the `MZ` magic, is not native.
    static func isNativePE(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let markerOffset = 0x40
        let headerLength = markerOffset + (wineSignatures.map(\.count).max() ?? 0)
        guard let header = try? handle.read(upToCount: headerLength),
              header.count == headerLength,
              header.prefix(2) == Data("MZ".utf8)
        else { return false }
        let stub = header.dropFirst(markerOffset)
        return !wineSignatures.contains { stub.starts(with: $0) }
    }
}
