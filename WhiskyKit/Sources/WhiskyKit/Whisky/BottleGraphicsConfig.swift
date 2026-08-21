//
//  BottleGraphicsConfig.swift
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
import os.log

/// The graphics translation backend for a Wine bottle.
///
/// Controls which Direct3D translation layer is used at launch time.
/// `.recommended` defers the choice to ``GraphicsBackendResolver`` which
/// selects the best concrete backend based on GPU and macOS heuristics.
public enum GraphicsBackend: String, Codable, CaseIterable, Equatable, Sendable {
    /// Let Whisky choose the best backend for the current system.
    case recommended
    /// Apple's Direct3D-to-Metal translation layer (Wine's built-in D3DMetal).
    case d3dMetal
    /// DXVK: Direct3D-to-Vulkan translation via MoltenVK.
    case dxvk
    /// DXMT: Direct3D-11-to-Metal translation. Requires a runtime that bundles
    /// the DXMT payload (Wine Libraries ≥ 3.1.0).
    case dxmt
    /// Wine's built-in OpenGL-based Direct3D translation.
    case wined3d

    /// A human-readable display name for this backend.
    public var displayName: String {
        switch self {
        case .recommended:
            String(localized: "config.graphics.backend.recommended")
        case .d3dMetal:
            "D3DMetal"
        case .dxvk:
            "DXVK"
        case .dxmt:
            "DXMT"
        case .wined3d:
            "WineD3D"
        }
    }

    /// Whether this backend can actually be used with the given installed
    /// runtime record. DXMT requires a runtime that bundles its payload
    /// (Wine Libraries ≥ 3.1.0, signalled by `dxmtVersion` in the runtime
    /// plist); every other backend ships with all runtimes. Pure so pickers
    /// and tests can inject a record; production callers pass
    /// `WhiskyWineInstaller.whiskyWineInfo()`.
    public func isAvailable(runtimeInfo: WhiskyWineVersion?) -> Bool {
        switch self {
        case .dxmt:
            runtimeInfo?.dxmtVersion != nil
        case .recommended, .d3dMetal, .dxvk, .wined3d:
            true
        }
    }

    /// A one-line summary suitable for selection cards or tooltips.
    public var summary: String {
        switch self {
        case .recommended:
            String(localized: "config.graphics.backend.recommended.summary")
        case .d3dMetal:
            String(localized: "config.graphics.backend.d3dMetal.summary")
        case .dxvk:
            String(localized: "config.graphics.backend.dxvk.summary")
        case .dxmt:
            String(localized: "config.graphics.backend.dxmt.summary")
        case .wined3d:
            String(localized: "config.graphics.backend.wined3d.summary")
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes a string-backed enum leniently: an absent key yields `nil`, and an
    /// unknown or wrong-typed value also yields `nil` (logged) instead of throwing
    /// out of the parent decode. This keeps settings written by a newer Whisky —
    /// one that added an enum case this build doesn't know — loadable, instead of
    /// a single unrecognized value bricking the whole bottle's settings.
    ///
    /// Only applies to `String`-raw-value enums; keyed-`Codable` enums
    /// (e.g. `EnhancedSync`, `DXVKHUD`) are not covered and still decode strictly.
    func decodeLenientIfPresent<T: RawRepresentable>(
        _: T.Type,
        forKey key: Key
    ) -> T? where T.RawValue == String {
        let typeName = String(describing: T.self)
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        let raw: String?
        do {
            raw = try decodeIfPresent(String.self, forKey: key)
        } catch let error as DecodingError {
            // A wrong-typed value (e.g. a number or object where a string was expected) is
            // corruption — it cannot be produced by any real Whisky build — so log at .error.
            Logger.wineKit.error(
                """
                Ignoring corrupt \(typeName, privacy: .public) at \
                `\(key.stringValue, privacy: .public)` (path: \(path, privacy: .public)): \
                \(String(describing: error), privacy: .public)
                """
            )
            return nil
        } catch {
            Logger.wineKit.error(
                """
                Ignoring malformed \(typeName, privacy: .public) at \
                `\(key.stringValue, privacy: .public)` (path: \(path, privacy: .public)): \
                \(String(describing: error), privacy: .public)
                """
            )
            return nil
        }
        guard let raw else { return nil }
        guard let value = T(rawValue: raw) else {
            // A well-formed string that this build doesn't recognize is legitimate
            // forward-compat (a newer Whisky added an enum case) — log at .warning.
            Logger.wineKit.warning(
                """
                Ignoring unknown \(typeName, privacy: .public) value `\(raw, privacy: .public)` at \
                `\(key.stringValue, privacy: .public)` (path: \(path, privacy: .public)); using default
                """
            )
            return nil
        }
        return value
    }
}

/// Stores the graphics backend choice for a bottle.
///
/// This config is serialized alongside other bottle config groups in
/// ``BottleSettings``. The defensive `init(from:)` decodes an unknown or
/// malformed backend value gracefully to `.recommended` (via
/// ``Swift/KeyedDecodingContainer/decodeLenientIfPresent(_:forKey:)``) rather
/// than throwing out of the whole settings decode.
public struct BottleGraphicsConfig: Codable, Equatable {
    /// The selected graphics backend. Defaults to `.recommended`.
    var backend: GraphicsBackend = .recommended

    /// Whether this bottle opts in to D3DMetal's DLSS-to-MetalFX path.
    ///
    /// On by default. This started off opt-in on the theory that a game finding
    /// the bridge takes its DLSS path instead of whatever it would otherwise
    /// have used, which could regress as easily as help. Measured, it helps, so
    /// the default flipped and the toggle stays for the titles it does not suit.
    /// A tree with no bridge in it is unaffected either way: with nothing for
    /// `DXGIAdapter::nvngxDLLLocation` to find, the variable is inert.
    var metalFX: Bool = true

    /// Creates a new graphics config with the default `.recommended` backend.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backend = container.decodeLenientIfPresent(GraphicsBackend.self, forKey: .backend) ?? .recommended
        // Matches the property default, so a bottle written before this key
        // existed adopts the new default instead of decoding as off.
        self.metalFX = (try? container.decodeIfPresent(Bool.self, forKey: .metalFX)) ?? true
    }
}
