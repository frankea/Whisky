//
//  Rosetta2.swift
//  Whisky
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

public class Rosetta2 {
    static let rosetta2RuntimeBin = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"

    /// Where ``isRosettaInstalled`` looks for the runtime library. Tests point
    /// it at a temporary file; the app never changes it.
    nonisolated(unsafe) static var runtimePath = rosetta2RuntimeBin

    /// Checked live, not cached at launch: a major macOS update can remove
    /// Rosetta, and a value frozen at launch would keep reporting it missing
    /// (and keep reopening setup) after it is reinstalled.
    public static var isRosettaInstalled: Bool {
        FileManager.default.fileExists(atPath: runtimePath)
    }

    public static func installRosetta() async throws -> Bool {
        let process = Process()
        let fileHandle = try Wine.makeFileHandle()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = ["--install-rosetta", "--agree-to-license"]
        fileHandle.writeApplicationInfo()

        let stream = try process.runStream(name: "Install Rosetta 2", fileHandle: fileHandle)
        var status: Int32 = 1
        for await output in stream {
            if case let .terminated(code) = output {
                status = code
            }
        }
        return status == 0
    }
}
