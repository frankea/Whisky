//
//  WineAudioEndpoint.swift
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

/// Registry layout Wine's CoreAudio driver uses to identify output devices.
///
/// Wine's mmdevapi reads `DefaultOutput` under the driver key and, when it
/// names an active endpoint, uses that device instead of the macOS default.
/// An endpoint ID is `{0.0.0.00000000}.{GUID}` (flow 0 is render), and each
/// device's GUID is stored as `REG_BINARY` `guid` under
/// `devices\0,<CoreAudio device UID>`. Wine keeps an existing GUID and only
/// generates one when none is stored, so Whisky can read or seed it.
enum WineAudioEndpoint {
    /// The per-driver key holding `DefaultOutput` and the `devices` subkeys.
    static let driverKey = #"HKCU\Software\Wine\Drivers\winecoreaudio.drv"#

    /// The registry value Wine reads to pick the default output endpoint.
    static let defaultOutputValue = "DefaultOutput"

    /// The registry value holding a device's endpoint GUID.
    static let guidValue = "guid"

    /// The key holding the endpoint GUID of a render device.
    ///
    /// - Returns: `nil` when `uid` is empty or contains a backslash, which
    ///   would make it a different registry path.
    static func renderDeviceKey(uid: String) -> String? {
        guard !uid.isEmpty, !uid.contains("\\") else { return nil }
        return driverKey + #"\devices\0,"# + uid
    }

    /// A GUID as Wine stores it in `REG_BINARY`: the in-memory `GUID` struct,
    /// so `Data1`, `Data2` and `Data3` are little-endian and `Data4` is as is.
    ///
    /// - Returns: 32 uppercase hex characters.
    static func registryHex(for uuid: UUID) -> String {
        guidBytes(for: uuid).map { String(format: "%02X", $0) }.joined()
    }

    /// The inverse of ``registryHex(for:)``.
    ///
    /// - Returns: `nil` unless the trimmed input is exactly 32 hex characters.
    static func uuid(fromRegistryHex hex: String) -> UUID? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        // Checked up front: UInt8(_:radix:) alone would also accept a "+" sign.
        guard trimmed.count == 32, trimmed.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        // The GUID byte swap is its own inverse.
        let uuidBytes = swapGUIDByteOrder(bytes)
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    /// The render endpoint ID Wine's `IMMDevice::GetId` reports for a device.
    ///
    /// Foundation's `uuidString` is already the Windows text form of a GUID.
    static func endpointID(for uuid: UUID) -> String {
        "{0.0.0.00000000}.{" + uuid.uuidString.uppercased() + "}"
    }

    private static func guidBytes(for uuid: UUID) -> [UInt8] {
        let raw = uuid.uuid
        let bytes = [
            raw.0, raw.1, raw.2, raw.3, raw.4, raw.5, raw.6, raw.7,
            raw.8, raw.9, raw.10, raw.11, raw.12, raw.13, raw.14, raw.15
        ]
        return swapGUIDByteOrder(bytes)
    }

    /// Converts between the big-endian RFC 4122 byte order and the Windows
    /// `GUID` memory layout by reversing `Data1`, `Data2` and `Data3`.
    private static func swapGUIDByteOrder(_ bytes: [UInt8]) -> [UInt8] {
        Array(bytes[0 ..< 4].reversed())
            + Array(bytes[4 ..< 6].reversed())
            + Array(bytes[6 ..< 8].reversed())
            + Array(bytes[8 ..< 16])
    }
}
