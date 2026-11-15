//
//  WinetricksInstallArguments.swift
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

/// The command line for installing one winetricks verb with nobody watching:
/// from a game configuration, a troubleshooting fix or the dependency panel.
public enum WinetricksInstallArguments {
    /// The arguments to run `/usr/bin/env` with to install `verb`.
    ///
    /// Every verb gets `-q` (W_OPT_UNATTENDED). Without it an installer shows
    /// its wizard and waits for a click nothing prompts for, so the process
    /// never exits and the winetricks.log entry is never written. It is not
    /// only installers: `w_try_regsvr32` adds `/S` only when unattended, so
    /// `xact` put up one "Successfully registered DLL" panel per audio DLL,
    /// each waiting on a click.
    ///
    /// The vcrun verbs also get `--force`: Microsoft rotates the vc_redist
    /// binaries in place, so the checksums pinned in the bundled winetricks go
    /// stale between releases and the install aborts with exit 1 on the SHA256
    /// mismatch (winetricks#2195).
    ///
    /// - Parameters:
    ///   - verb: The winetricks verb to install.
    ///   - winetricksPath: The path of the bundled winetricks script.
    /// - Returns: `bash`, the script, its options and the verb.
    public static func arguments(verb: String, winetricksPath: String) -> [String] {
        var arguments = ["bash", winetricksPath]
        if verb.hasPrefix("vcrun") {
            arguments.append("--force")
        }
        arguments.append("-q")
        arguments.append(verb)
        return arguments
    }
}
