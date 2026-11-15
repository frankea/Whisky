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

    /// The bundled DXMT version recorded alongside the runtime version,
    /// e.g. `"0.80"`. Optional so runtime plists from before v3.1.0 (which
    /// introduced the DXMT payload) still decode; `nil` also signals to the
    /// app that the installed runtime cannot offer the DXMT backend.
    public var dxmtVersion: String?

    /// The expected SHA-256 of the `Libraries.tar.gz` archive for this runtime
    /// version, as a lowercase hex string. When present, the downloader verifies
    /// the fetched archive against it before installing. Optional so runtime
    /// plists written before this key existed still decode (and so the download
    /// path stays backward-compatible when no hash is advertised).
    public var sha256: String?

    /// Whether this runtime's Wine build can execute Apple's GPTK/D3DMetal
    /// payload. The payload's forwarder DLLs are C++ with exception handling,
    /// and unwinding them requires personality-routine support for builtin
    /// modules that upstream Wine lacks — on a build without it, every process
    /// that runs D3DMetal code dies on its first internal throw. Absent (all
    /// runtimes to date) means not capable; a future GPTK-ready runtime build
    /// advertises `true` here.
    public var gptkCapable: Bool?

    /// Whether this runtime's Wine implements msync and esync.
    ///
    /// Wine only takes either path when its own `ntdll.so` and `wineserver`
    /// read `WINEMSYNC` and `WINEESYNC`. In Wine Libraries 3.1.1 (upstream
    /// Wine 11.0) neither name appears in either binary, so Wine ignores the
    /// Enhanced Sync setting. Whisky still sets the variables, because
    /// D3DMetal checks `WINEESYNC` itself (the enhanced sync block of
    /// `BottleSettings.populateBottleManagedLayer`).
    ///
    /// A runtime whose Wine carries the msync patches advertises `true` here.
    /// No published plist sets it yet, so ``implementsEnhancedSync`` decides
    /// an absent key by lineage. To check a build, run `strings` on its
    /// `ntdll.so` and `wineserver` and look for `WINEMSYNC` and `WINEESYNC`.
    public var msyncCapable: Bool?

    /// Whether the Enhanced Sync setting changes how this runtime's Wine
    /// synchronizes threads, rather than only how D3DMetal behaves.
    ///
    /// An explicit ``msyncCapable`` wins. Without it, the runtime counts as
    /// capable when it is ``gptkCapable``: only the CrossOver-based v4
    /// engines set that key, and they implement msync and esync, while the
    /// stock 3.x runtimes set neither key and implement neither. The v4
    /// betas installed by hand carry plists written before `msyncCapable`
    /// existed, so this keeps them from being told their engine ignores the
    /// setting.
    public var implementsEnhancedSync: Bool {
        msyncCapable ?? (gptkCapable == true)
    }

    enum CodingKeys: String, CodingKey {
        case version
        case dxvkVersion
        case dxmtVersion
        case sha256
        case gptkCapable
        case msyncCapable
    }

    public init(
        version: SemanticVersion,
        dxvkVersion: String? = nil,
        dxmtVersion: String? = nil,
        sha256: String? = nil,
        gptkCapable: Bool? = nil,
        msyncCapable: Bool? = nil
    ) {
        self.version = version
        self.dxvkVersion = Self.normalized(dxvkVersion)
        self.dxmtVersion = Self.normalized(dxmtVersion)
        self.sha256 = Self.normalizedDigest(sha256)
        self.gptkCapable = gptkCapable
        self.msyncCapable = msyncCapable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let versionDict = try container.nestedContainer(keyedBy: VersionKeys.self, forKey: .version)
        let major = try versionDict.decode(Int.self, forKey: .major)
        let minor = try versionDict.decode(Int.self, forKey: .minor)
        let patch = try versionDict.decode(Int.self, forKey: .patch)
        version = SemanticVersion(major, minor, patch)
        dxvkVersion = try Self.normalized(container.decodeIfPresent(String.self, forKey: .dxvkVersion))
        dxmtVersion = try Self.normalized(container.decodeIfPresent(String.self, forKey: .dxmtVersion))
        sha256 = try Self.normalizedDigest(container.decodeIfPresent(String.self, forKey: .sha256))
        gptkCapable = try container.decodeIfPresent(Bool.self, forKey: .gptkCapable)
        msyncCapable = try container.decodeIfPresent(Bool.self, forKey: .msyncCapable)
    }

    /// Collapses an empty string to `nil` so "absent" and "blank" map to the
    /// same state (and never render as a dangling `DXVK:` line).
    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Normalizes an advertised SHA-256: trims surrounding whitespace, lowercases,
    /// and requires exactly 64 hex characters. A blank or malformed value (a
    /// publisher typo, truncated paste, placeholder) collapses to `nil` so that
    /// release simply goes unverified, rather than failing every download against
    /// an impossible digest — which would brick installs with a misleading
    /// "download corrupted" error. Integrity here is a corruption tripwire, not
    /// supply-chain trust, so degrading to "unverified" on bad metadata is the
    /// safer failure mode.
    private static func normalizedDigest(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // ASCII-only: `Character.isHexDigit` also matches fullwidth Unicode hex
        // forms, which can never equal CryptoKit's `%02x` output — so without the
        // `isASCII` guard a fullwidth digest would pass here and then fail every
        // download as a mismatch instead of collapsing to nil (skip).
        let isHexDigest = trimmed.count == 64 && trimmed.allSatisfy { $0.isHexDigit && $0.isASCII }
        return isHexDigest ? trimmed : nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var versionDict = container.nestedContainer(keyedBy: VersionKeys.self, forKey: .version)
        try versionDict.encode(version.major, forKey: .major)
        try versionDict.encode(version.minor, forKey: .minor)
        try versionDict.encode(version.patch, forKey: .patch)
        try container.encodeIfPresent(dxvkVersion, forKey: .dxvkVersion)
        try container.encodeIfPresent(dxmtVersion, forKey: .dxmtVersion)
        try container.encodeIfPresent(sha256, forKey: .sha256)
        try container.encodeIfPresent(gptkCapable, forKey: .gptkCapable)
        try container.encodeIfPresent(msyncCapable, forKey: .msyncCapable)
    }

    private enum VersionKeys: String, CodingKey {
        case major, minor, patch
    }
}
