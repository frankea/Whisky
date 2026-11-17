//
//  Wine+ServerStart.swift
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

public extension Wine {
    /// Where wineservers keep their sockets: `/tmp/.wine-<uid>`.
    static var wineserverRoot: URL {
        URL(fileURLWithPath: "/tmp/.wine-\(getuid())", isDirectory: true)
    }

    /// When a bottle's running wineserver started, or `nil` if none is running.
    ///
    /// A wineserver keeps its socket in `<root>/server-<device>-<inode>/socket`,
    /// named after the prefix folder's device and inode numbers in hex. It
    /// creates the socket when it starts and removes it when it exits, so the
    /// socket's creation date is the server's start time. Reads the file system
    /// only; never starts or signals a wineserver.
    ///
    /// - Parameters:
    ///   - prefixURL: The bottle's folder (its Wine prefix).
    ///   - root: The folder wineservers keep their sockets in.
    /// - Returns: The socket's creation date, or `nil` when there is no socket or it can't be read.
    static func wineserverStartDate(forPrefix prefixURL: URL, root: URL = wineserverRoot) -> Date? {
        var info = stat()
        // stat, not lstat: Wine names the folder after the prefix it resolves to.
        guard stat(prefixURL.path(percentEncoded: false), &info) == 0 else { return nil }
        // Wine prints both as `%llx` of the values widened to 64 bits.
        let device = UInt64(bitPattern: Int64(info.st_dev))
        let folder = "server-\(String(device, radix: 16))-\(String(UInt64(info.st_ino), radix: 16))"
        let socket = root.appending(path: folder).appending(path: "socket")
        return try? socket.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}
