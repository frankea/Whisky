//
//  WhiskyWineVersion.swift
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
import SemanticVersion

/// Represents the version information structure from WhiskyWineVersion.plist
/// The plist format uses a nested dictionary structure:
/// ```
/// <key>version</key>
/// <dict>
///     <key>major</key>
///     <integer>2</integer>
///     <key>minor</key>
///     <integer>5</integer>
///     <key>patch</key>
///     <integer>0</integer>
/// </dict>
/// ```
public struct WhiskyWineVersion: Codable {
    public var version: SemanticVersion

    /// The bundled DXVK (macOS) version recorded alongside the runtime version,
    /// e.g. `"1.10.3"`. Optional so runtime plists written before this key
    /// existed still decode.
    public var dxvkVersion: String?

    enum CodingKeys: String, CodingKey {
        case version
        case dxvkVersion
    }

    public init(version: SemanticVersion, dxvkVersion: String? = nil) {
        self.version = version
        self.dxvkVersion = dxvkVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let versionDict = try container.nestedContainer(keyedBy: VersionKeys.self, forKey: .version)
        let major = try versionDict.decode(Int.self, forKey: .major)
        let minor = try versionDict.decode(Int.self, forKey: .minor)
        let patch = try versionDict.decode(Int.self, forKey: .patch)
        version = SemanticVersion(major, minor, patch)
        dxvkVersion = try container.decodeIfPresent(String.self, forKey: .dxvkVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var versionDict = container.nestedContainer(keyedBy: VersionKeys.self, forKey: .version)
        try versionDict.encode(version.major, forKey: .major)
        try versionDict.encode(version.minor, forKey: .minor)
        try versionDict.encode(version.patch, forKey: .patch)
        try container.encodeIfPresent(dxvkVersion, forKey: .dxvkVersion)
    }

    private enum VersionKeys: String, CodingKey {
        case major, minor, patch
    }
}
