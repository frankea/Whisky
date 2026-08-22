//
//  DiscordPresence.swift
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

import Darwin
import Foundation
import os.log

/// Publishes what a bottle is running to the Discord client, as Whisky.
///
/// This is the half that does not involve Wine at all: Whisky already knows
/// which program it launched, and Discord's socket is reachable from the host
/// side, so the presence is written directly. It covers every program in a
/// bottle, including the ones that have never heard of Discord, where
/// ``DiscordBridge`` only carries presence for games that publish their own.
///
/// Discord attributes the activity to the application the `client_id` belongs
/// to, so this reads as Whisky with the program named underneath, the shape
/// other launchers use. The program name is the only thing sent.
public actor DiscordPresence {
    public static let shared = DiscordPresence()

    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "DiscordPresence")

    /// The Discord application this presence is published under, when a build
    /// carries no id of its own.
    ///
    /// Empty, and meant to stay that way. The id belongs to a Discord
    /// application someone owns, and the name and artwork users see come from
    /// that application rather than from anything here, so it is not the
    /// repository's to carry. See ``clientID`` for how a build supplies one.
    public static let defaultClientID = ""

    /// The client id in effect, or `nil` when none has been configured.
    ///
    /// Three sources, first non-empty wins: `WHISKY_DISCORD_CLIENT_ID` in the
    /// environment, for testing against your own application; `Local/client-id.txt`
    /// beside this module's resources, which is how a build carries an id the
    /// repository does not; and ``defaultClientID``.
    public static var clientID: String? {
        resolveClientID(
            environment: ProcessInfo.processInfo.environment,
            bundled: bundledClientID,
            fallback: defaultClientID
        )
    }

    static func resolveClientID(environment: [String: String], bundled: String?, fallback: String) -> String? {
        for candidate in [environment["WHISKY_DISCORD_CLIENT_ID"], bundled, fallback] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// The id a build was assembled with, if it was given one. The file is
    /// ignored by git, so a checkout has none and presence stays dark.
    private static var bundledClientID: String? {
        guard let url = Bundle.module.url(
            forResource: "client-id", withExtension: "txt", subdirectory: "Local"
        )
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Whether a presence can be published at all.
    public static var isAvailable: Bool { clientID != nil }

    private let clientID: String?
    private let socketDirectory: URL
    private var descriptor: Int32 = -1
    private var published: String?

    private var isConnected: Bool { descriptor >= 0 }

    /// Both dependencies are injected so a test can point an instance at its own
    /// socket; ``shared`` takes the configured id and the real directory.
    public init(clientID: String? = DiscordPresence.clientID, socketDirectory: URL = DiscordIPC.socketDirectory) {
        self.clientID = clientID
        self.socketDirectory = socketDirectory
    }

    /// Publishes `program` as the current activity, connecting first if needed.
    ///
    /// Repeating the same program is a no-op, so a caller may call this as often
    /// as it likes. Any failure disconnects and is logged rather than thrown:
    /// a presence that cannot be published must never affect the launch that
    /// asked for it.
    public func publish(program: String, startedAt: Date = Date()) {
        guard let clientID else { return }
        guard published != program else { return }

        do {
            if !isConnected {
                try connect(clientID: clientID)
            }
            try send(opcode: .frame, payload: DiscordIPC.encoder.encode(
                DiscordCommand.setActivity(program: program, startedAt: startedAt)
            ))
            published = program
            Self.logger.info("Published Discord presence for \(program, privacy: .public)")
        } catch {
            Self.logger.warning("Could not publish Discord presence: \(error.localizedDescription, privacy: .public)")
            disconnect()
        }
    }

    /// Clears the activity and drops the connection.
    public func clear() {
        guard isConnected else {
            published = nil
            return
        }

        if let payload = try? DiscordIPC.encoder.encode(DiscordCommand.clearActivity()) {
            try? send(opcode: .frame, payload: payload)
        }
        disconnect()
    }

    /// Connects to the first Discord socket that answers.
    ///
    /// Every index gets a connection attempt rather than only the first one
    /// present: Discord leaves its socket file behind when it exits, so the
    /// common state on a Mac that has run Discord is a dead `discord-ipc-0`
    /// sitting in front of the live socket.
    private func connect(clientID: String) throws {
        var lastError = DiscordPresenceError.discordNotRunning

        for index in DiscordIPC.socketIndices {
            let url = DiscordIPC.socketURL(index: index, in: socketDirectory)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }

            do {
                descriptor = try Self.openSocket(at: url)
            } catch let error as DiscordPresenceError {
                lastError = error
                continue
            }

            do {
                try send(opcode: .handshake, payload: DiscordIPC.encoder.encode(DiscordHandshake(clientID: clientID)))
                try readHandshakeReply()
                return
            } catch {
                disconnect()
                throw error
            }
        }

        throw lastError
    }

    private static func openSocket(at url: URL) throws -> Int32 {
        let path = url.path(percentEncoded: false)
        guard var address = makeAddress(for: path) else { throw DiscordPresenceError.socketPathTooLong(path) }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw DiscordPresenceError.socketUnavailable(errno) }

        // Without this, writing to a socket Discord has closed raises SIGPIPE
        // and takes Whisky down with it.
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.connect(descriptor, address, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            close(descriptor)
            throw DiscordPresenceError.connectionFailed(code)
        }

        return descriptor
    }

    private func disconnect() {
        if descriptor >= 0 { close(descriptor) }
        descriptor = -1
        published = nil
    }

    private func send(opcode: DiscordIPC.Opcode, payload: Data) throws {
        let frame = DiscordIPC.encode(opcode: opcode, payload: payload)
        let descriptor = self.descriptor

        try frame.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0

            while offset < buffer.count {
                let sent = Darwin.send(descriptor, base.advanced(by: offset), buffer.count - offset, 0)
                guard sent > 0 else { throw DiscordPresenceError.writeFailed(errno) }
                offset += sent
            }
        }
    }

    /// Reads Discord's answer to the handshake.
    ///
    /// A closed connection means the handshake was rejected, an unknown client
    /// id usually, and is worth failing on. A read timeout is not: the socket
    /// is still open, and a presence that Discord has not acknowledged yet is
    /// better than no presence.
    private func readHandshakeReply() throws {
        var buffer = [UInt8](repeating: 0, count: 1_024)
        let received = recv(descriptor, &buffer, buffer.count, 0)

        if received == 0 { throw DiscordPresenceError.handshakeRejected }
        guard received > 0 else { return }

        if let frame = DiscordIPC.decode(Data(buffer.prefix(received))),
           let text = String(data: frame.payload, encoding: .utf8),
           text.contains("\"evt\":\"ERROR\"") {
            Self.logger.warning("Discord refused the handshake: \(text, privacy: .public)")
            throw DiscordPresenceError.handshakeRejected
        }
    }

    private static func makeAddress(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes)
        }
        return address
    }
}

/// Why a presence could not be published. Every case is recoverable: the next
/// launch tries again from scratch.
public enum DiscordPresenceError: Error, LocalizedError, Equatable {
    case discordNotRunning
    case socketPathTooLong(String)
    case socketUnavailable(Int32)
    case connectionFailed(Int32)
    case writeFailed(Int32)
    case handshakeRejected

    public var errorDescription: String? {
        switch self {
        case .discordNotRunning:
            "No Discord socket in \(DiscordIPC.socketDirectory.path(percentEncoded: false))"
        case let .socketPathTooLong(path):
            "Socket path does not fit a unix address: \(path)"
        case let .socketUnavailable(code):
            "socket() failed with errno \(code)"
        case let .connectionFailed(code):
            "connect() failed with errno \(code)"
        case let .writeFailed(code):
            "send() failed with errno \(code)"
        case .handshakeRejected:
            "Discord closed the connection during the handshake"
        }
    }
}

// MARK: - Wire payloads

/// The payload types are file-scope rather than nested in ``DiscordPresence``
/// because each of them needs a `CodingKeys` of its own, and one more level of
/// nesting would put those two deep.

struct DiscordHandshake: Encodable {
    let version = 1
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case clientID
    }
}

struct DiscordActivity: Encodable {
    struct Timestamps: Encodable {
        let start: Int
    }

    /// Named for artwork uploaded to the Discord application. Until the
    /// application exists Discord simply shows no image for them.
    struct Assets: Encodable {
        let largeImage: String
        let largeText: String
    }

    let details: String
    let timestamps: Timestamps
    let assets = Assets(largeImage: "whisky", largeText: "Whisky")
}

struct DiscordActivityArguments: Encodable {
    /// Discord drops the activity when this process exits, which is the
    /// backstop for Whisky quitting without clearing.
    let pid: Int32
    let activity: DiscordActivity?

    enum CodingKeys: String, CodingKey {
        case pid, activity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pid, forKey: .pid)
        // An absent key leaves the previous activity standing; clearing needs
        // the key present and null.
        if let activity {
            try container.encode(activity, forKey: .activity)
        } else {
            try container.encodeNil(forKey: .activity)
        }
    }
}

struct DiscordCommand: Encodable {
    let cmd = "SET_ACTIVITY"
    let nonce: String
    let args: DiscordActivityArguments

    static func setActivity(program: String, startedAt: Date) -> DiscordCommand {
        DiscordCommand(
            nonce: UUID().uuidString,
            args: DiscordActivityArguments(
                pid: ProcessInfo.processInfo.processIdentifier,
                activity: DiscordActivity(
                    details: program,
                    timestamps: DiscordActivity.Timestamps(start: Int(startedAt.timeIntervalSince1970))
                )
            )
        )
    }

    static func clearActivity() -> DiscordCommand {
        DiscordCommand(
            nonce: UUID().uuidString,
            args: DiscordActivityArguments(pid: ProcessInfo.processInfo.processIdentifier, activity: nil)
        )
    }
}
