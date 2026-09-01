//
//  VCRuntimeFallback.swift
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

/// Marker-file fallback detection for the Visual C++ Runtime dependency.
///
/// The winetricks.log entry for a verb is written only after the verb's
/// installer process exits. The vc_redist installer is known to hang under
/// wine after installing successfully, so the runtime can be fully present
/// while the log (and thus verb-based detection) says it is not
/// (frankea/Whisky#233).
///
/// The probe keys on `system32/mfc140.dll`. Wine never ships mfc140.dll as
/// a builtin, so it only appears after a real redist install; msvcp140.dll
/// and vcruntime140.dll are builtins in every fresh prefix and cannot serve
/// as a signal. On win64 bottles system32 holds the 64-bit DLLs, so the
/// probe keys on the x64 redist's own payload -- deliberately not on
/// winetricks' bookkeeping path: its `installed_file1` expands
/// `W_SYSTEM32_DLLS_WIN`, which is `C:\windows\syswow64` on win64 and
/// system32 only on win32, where the two coincide. mfc140.dll in syswow64
/// alone is the partial install from #233 (the x86 half landed, the x64
/// half hung) and must not count as installed, so the panel keeps offering
/// the rerun that repairs it.
///
/// This probe is a fallback, scoped to the `vcruntime` definition, and is
/// only consulted when verb-based detection found the required verbs
/// missing -- a bottle whose log already says installed is never probed.
public enum VCRuntimeFallback {
    /// The probe file, relative to drive_c: the x64 redist's mfc140.dll on
    /// win64 bottles (where system32 is the 64-bit directory); on win32 the
    /// same path is winetricks' own `installed_file1` marker.
    ///
    /// Not a Wine builtin; only a real redist install places it here.
    public static let markerFile = "windows/system32/mfc140.dll"

    /// Returns whether the Visual C++ Runtime should be considered installed
    /// based on the marker file, for a definition whose verbs were not found.
    ///
    /// - Parameters:
    ///   - definition: The dependency definition being checked.
    ///   - missingVerbs: The definition's verbs that verb-based detection
    ///     did not find. An empty array means the log already says installed,
    ///     in which case the filesystem is never probed.
    ///   - bottleURL: The bottle directory containing `drive_c`.
    /// - Returns: `true` when the definition is `vcruntime`, its verbs are
    ///   missing from the log, and the marker file is present.
    public static func detectsInstallation(
        definition: DependencyDefinition,
        missingVerbs: [String],
        bottleURL: URL
    ) -> Bool {
        guard definition.id == "vcruntime", !missingVerbs.isEmpty else {
            return false
        }

        let marker = bottleURL
            .appending(path: "drive_c")
            .appending(path: markerFile)
        return FileManager.default.fileExists(atPath: marker.path(percentEncoded: false))
    }
}
