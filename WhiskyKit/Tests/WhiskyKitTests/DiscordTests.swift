//
//  DiscordTests.swift
//  WhiskyKitTests
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
import Testing
@testable import WhiskyKit

@Suite("Discord IPC Tests")
struct DiscordIPCTests {
    @Test("A frame is an opcode and a length, little-endian, then the payload")
    func framingLayout() throws {
        let payload = Data("{\"v\":1}".utf8)
        let frame = DiscordIPC.encode(opcode: .handshake, payload: payload)

        #expect(frame.count == 8 + payload.count)
        #expect([UInt8](frame.prefix(4)) == [0, 0, 0, 0])
        #expect([UInt8](frame.dropFirst(4).prefix(4)) == [UInt8(payload.count), 0, 0, 0])
        #expect(Data(frame.dropFirst(8)) == payload)
    }

    @Test("A frame decodes back to what was encoded")
    func framingRoundTrip() throws {
        let payload = Data(#"{"cmd":"SET_ACTIVITY"}"#.utf8)
        let decoded = try #require(DiscordIPC.decode(DiscordIPC.encode(opcode: .frame, payload: payload)))

        #expect(decoded.opcode == DiscordIPC.Opcode.frame.rawValue)
        #expect(decoded.payload == payload)
    }

    @Test("A payload longer than 255 bytes still round-trips")
    func framingWideLength() throws {
        let payload = Data(repeating: 0x41, count: 300)
        let decoded = try #require(DiscordIPC.decode(DiscordIPC.encode(opcode: .frame, payload: payload)))

        #expect(decoded.payload.count == 300)
    }

    @Test("An incomplete frame decodes to nothing rather than to garbage")
    func framingIncomplete() {
        let frame = DiscordIPC.encode(opcode: .frame, payload: Data(repeating: 0x41, count: 32))

        #expect(DiscordIPC.decode(Data(frame.prefix(4))) == nil)
        #expect(DiscordIPC.decode(Data(frame.prefix(20))) == nil)
    }

    @Test("Extra bytes after a frame are left alone")
    func framingTrailingBytes() throws {
        let payload = Data("hi".utf8)
        var frame = DiscordIPC.encode(opcode: .frame, payload: payload)
        frame.append(Data(repeating: 0xFF, count: 16))

        let decoded = try #require(DiscordIPC.decode(frame))
        #expect(decoded.payload == payload)
    }

    @Test("Socket discovery takes the lowest index present")
    func socketDiscovery() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(DiscordIPC.availableSocket(in: directory) == nil)

        for index in [3, 7] {
            try Data().write(to: DiscordIPC.socketURL(index: index, in: directory))
        }

        #expect(DiscordIPC.availableSocket(in: directory) == DiscordIPC.socketURL(index: 3, in: directory))
    }
}

@Suite("Discord Presence Tests")
struct DiscordPresenceTests {
    private func encode(_ value: some Encodable) throws -> String {
        let encoder = DiscordIPC.encoder
        encoder.outputFormatting = [.sortedKeys]
        return try #require(try String(bytes: encoder.encode(value), encoding: .utf8))
    }

    @Test("The handshake names the protocol version and the client id")
    func handshakePayload() throws {
        let json = try encode(DiscordHandshake(clientID: "42"))

        #expect(json == #"{"client_id":"42","v":1}"#)
    }

    @Test("Setting an activity carries the program name and a start time")
    func setActivityPayload() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let json = try encode(DiscordCommand.setActivity(program: "ReadyOrNot", startedAt: started))

        #expect(json.contains(#""cmd":"SET_ACTIVITY""#))
        #expect(json.contains(#""details":"ReadyOrNot""#))
        #expect(json.contains(#""start":1700000000"#))
        #expect(json.contains(#""pid":"#))
        // Discord reads snake_case; a camelCase key is silently ignored.
        #expect(json.contains(#""large_image":"whisky""#))
    }

    @Test("Clearing sends an explicit null activity, not an absent one")
    func clearActivityPayload() throws {
        let json = try encode(DiscordCommand.clearActivity())

        // An absent key leaves the previous activity standing in Discord.
        #expect(json.contains(#""activity":null"#))
    }

    @Test("A build with no client id reports itself unavailable")
    func availabilityFollowsClientID() {
        #expect(DiscordPresence.isAvailable == (DiscordPresence.clientID != nil))
    }
}

/// A stand-in for the Discord client: binds a unix socket, answers the
/// handshake the way Discord does, and keeps everything written to it.
private final class FakeDiscordClient: @unchecked Sendable {
    private let listener: Int32
    private let lock = NSLock()
    private var received = Data()

    var frames: [(opcode: UInt32, payload: Data)] {
        lock.lock()
        defer { lock.unlock() }

        var remaining = received
        var frames: [(opcode: UInt32, payload: Data)] = []
        while let frame = DiscordIPC.decode(remaining) {
            frames.append(frame)
            remaining = Data(remaining.dropFirst(8 + frame.payload.count))
        }
        return frames
    }

    init?(path: String) {
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { return nil }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 1) == 0 else {
            close(listener)
            return nil
        }

        DispatchQueue.global().async { [self] in serve() }
    }

    deinit { close(listener) }

    private func serve() {
        let connection = accept(listener, nil, nil)
        guard connection >= 0 else { return }
        defer { close(connection) }

        var buffer = [UInt8](repeating: 0, count: 4_096)
        var greeted = false

        while true {
            let count = recv(connection, &buffer, buffer.count, 0)
            guard count > 0 else { return }

            lock.lock()
            received.append(contentsOf: buffer[0 ..< count])
            lock.unlock()

            if !greeted {
                greeted = true
                let ready = DiscordIPC.encode(
                    opcode: .frame, payload: Data(#"{"cmd":"DISPATCH","evt":"READY"}"#.utf8)
                )
                _ = ready.withUnsafeBytes { send(connection, $0.baseAddress, $0.count, 0) }
            }
        }
    }
}

@Suite("Discord Presence Socket Tests")
struct DiscordPresenceSocketTests {
    /// Short on purpose: the whole path has to fit `sun_path`, which is 104 bytes.
    private func makeSocketDirectory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitForFrames(_ count: Int, from client: FakeDiscordClient) async {
        for _ in 0 ..< 100 where client.frames.count < count {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("A presence reaches Discord past a socket Discord left behind")
    func publishesOverALiveSocket() async throws {
        let directory = try makeSocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Index 0 is a leftover file with nothing behind it, which is what a Mac
        // that has run Discord looks like once Discord exits.
        try Data().write(to: DiscordIPC.socketURL(index: 0, in: directory))
        let path = DiscordIPC.socketURL(index: 1, in: directory).path(percentEncoded: false)
        let client = try #require(FakeDiscordClient(path: path))

        let presence = DiscordPresence(clientID: "1234567890", socketDirectory: directory)
        await presence.publish(program: "ReadyOrNot")
        await waitForFrames(2, from: client)

        let frames = client.frames
        #expect(frames.count == 2)

        let handshake = try #require(String(bytes: frames[0].payload, encoding: .utf8))
        #expect(frames[0].opcode == DiscordIPC.Opcode.handshake.rawValue)
        #expect(handshake.contains(#""client_id":"1234567890""#))

        let activity = try #require(String(bytes: frames[1].payload, encoding: .utf8))
        #expect(frames[1].opcode == DiscordIPC.Opcode.frame.rawValue)
        #expect(activity.contains(#""details":"ReadyOrNot""#))

        await presence.clear()
        await waitForFrames(3, from: client)
        let cleared = try #require(String(bytes: client.frames[2].payload, encoding: .utf8))
        #expect(cleared.contains(#""activity":null"#))
    }

    @Test("With nothing listening, publishing gives up quietly")
    func publishesNothingWithoutDiscord() async throws {
        let directory = try makeSocketDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let presence = DiscordPresence(clientID: "1234567890", socketDirectory: directory)
        await presence.publish(program: "ReadyOrNot")
        await presence.clear()
    }
}

@Suite("Discord Bridge Tests")
struct DiscordBridgeTests {
    @Test("The relay ships with the build")
    func executableIsBundled() throws {
        let url = try #require(DiscordBridge.executableURL)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int

        #expect(url.lastPathComponent == "WhiskyDiscordBridge.exe")
        #expect((size ?? 0) > 0)
    }

    @Test("The relay is a 64-bit PE, matching the Wine the bottles run")
    func executableIsPE64() throws {
        let url = try #require(DiscordBridge.executableURL)
        let contents = try Data(contentsOf: url)

        #expect(contents.prefix(2) == Data("MZ".utf8))
        let peOffset = Int(contents[0x3C]) | Int(contents[0x3D]) << 8
        #expect(Data(contents[peOffset ..< (peOffset + 4)]) == Data([0x50, 0x45, 0x00, 0x00]))
        // IMAGE_FILE_MACHINE_AMD64
        #expect(contents[peOffset + 4] == 0x64 && contents[peOffset + 5] == 0x86)
    }

    @Test("Launching starts the relay detached, with the socket directory passed in")
    func launchArguments() {
        let executable = URL(fileURLWithPath: "/Applications/Whisky.app/Contents/bridge.exe")
        let directory = URL(fileURLWithPath: "/var/folders/49/abc/T", isDirectory: true)

        let arguments = DiscordBridge.launchArguments(executableURL: executable, socketDirectory: directory)

        // The relay appends the socket name to whatever it is given, so the
        // trailing separator a directory URL carries is what it wants.
        #expect(arguments == [
            "start", "/unix", "/Applications/Whisky.app/Contents/bridge.exe",
            "--dir", "/var/folders/49/abc/T/"
        ])
    }
}

@Suite("Bottle Discord Config Tests")
struct BottleDiscordConfigTests {
    @Test("Both switches are off until asked for")
    func defaultsAreOff() {
        let settings = BottleSettings()

        #expect(settings.discordPresence == false)
        #expect(settings.discordBridge == false)
    }

    @Test("Settings written before this feature existed still decode")
    func decodesLegacySettings() throws {
        let settings = try JSONDecoder().decode(BottleSettings.self, from: Data("{}".utf8))

        #expect(settings.discordPresence == false)
        #expect(settings.discordBridge == false)
    }

    @Test("A malformed value falls back to off instead of failing the whole decode")
    func toleratesMalformedValues() throws {
        let config = try JSONDecoder().decode(
            BottleDiscordConfig.self, from: Data(#"{"presence":"yes","bridge":true}"#.utf8)
        )

        #expect(config.presence == false)
        #expect(config.bridge == true)
    }

    @Test("Both switches survive a settings round trip")
    func roundTrip() throws {
        var settings = BottleSettings()
        settings.discordPresence = true
        settings.discordBridge = true

        let decoded = try JSONDecoder().decode(BottleSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.discordPresence == true)
        #expect(decoded.discordBridge == true)
    }
}
