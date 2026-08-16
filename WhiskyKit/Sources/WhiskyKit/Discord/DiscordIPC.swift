//
//  DiscordIPC.swift
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

/// Where the Discord client listens, and how a message is framed on the way in.
///
/// Both halves of Whisky's Discord support build on this. ``DiscordPresence``
/// connects to the socket and writes frames itself; ``DiscordBridge`` only needs
/// ``socketDirectory``, which it hands to the in-bottle relay. The framing is
/// identical on Windows and macOS, a little-endian opcode and length then
/// JSON, which is the reason that relay can be a byte pump rather than a
/// protocol implementation.
public enum DiscordIPC {
    /// Transport opcodes. Rich presence only ever uses the first two.
    public enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
        case ping = 3
        case pong = 4
    }

    /// The socket indices Discord's client libraries walk, in order.
    public static let socketIndices = 0 ..< 10

    /// The directory the Discord client puts its sockets in.
    ///
    /// Discord and Whisky are both unsandboxed, so `NSTemporaryDirectory()`
    /// resolves to the same per-user `TMPDIR` for each of them. A sandboxed app
    /// would get a container-private directory here and find nothing.
    public static var socketDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// The socket at `index`, whether or not anything is listening on it.
    public static func socketURL(index: Int, in directory: URL = socketDirectory) -> URL {
        directory.appending(path: "discord-ipc-\(index)")
    }

    /// The first Discord socket present, or `nil` when Discord is not running.
    public static func availableSocket(
        in directory: URL = socketDirectory, fileManager: FileManager = .default
    ) -> URL? {
        socketIndices
            .lazy
            .map { socketURL(index: $0, in: directory) }
            .first { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// The encoder every payload on this transport goes through.
    ///
    /// Discord's keys are snake_case. Converting them here keeps `CodingKeys`
    /// out of the payload types that would otherwise need one only for that.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    /// Frames a payload for the wire.
    public static func encode(opcode: Opcode, payload: Data) -> Data {
        var frame = Data(capacity: 8 + payload.count)
        for value in [opcode.rawValue, UInt32(payload.count)] {
            frame.append(UInt8(value & 0xFF))
            frame.append(UInt8((value >> 8) & 0xFF))
            frame.append(UInt8((value >> 16) & 0xFF))
            frame.append(UInt8((value >> 24) & 0xFF))
        }
        frame.append(payload)
        return frame
    }

    /// Reads one frame, or `nil` if `frame` does not hold a whole one yet.
    public static func decode(_ frame: Data) -> (opcode: UInt32, payload: Data)? {
        guard frame.count >= 8 else { return nil }
        let header = [UInt8](frame.prefix(8))

        func value(at offset: Int) -> UInt32 {
            UInt32(header[offset])
                | UInt32(header[offset + 1]) << 8
                | UInt32(header[offset + 2]) << 16
                | UInt32(header[offset + 3]) << 24
        }

        let length = Int(value(at: 4))
        let payload = frame.dropFirst(8)
        guard payload.count >= length else { return nil }
        return (value(at: 0), Data(payload.prefix(length)))
    }
}
