//
//  WineVirtualDesktopRegistry.swift
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

/// Whether a bottle's programs run in Wine's virtual desktop is decided by the
/// registry: a `Desktop` value in `HKCU\Software\Wine\Explorer` names the
/// desktop, and `Explorer\Desktops` optionally holds its size. The bottle's
/// `virtualDesktopEnabled` setting only mirrors it, and goes stale when the
/// registry changes elsewhere, for example in winecfg.
public extension Wine {
    internal enum VirtualDesktopRegistryKey: String {
        case explorer = #"HKCU\Software\Wine\Explorer"#
        case desktops = #"HKCU\Software\Wine\Explorer\Desktops"#
    }

    /// Reads one registry string value: `(key, value name)` to its data, or
    /// `nil` when the value is missing.
    typealias RegistryStringQuery = @MainActor (_ key: String, _ name: String) async throws -> String?

    /// Whether the bottle's registry turns Wine's virtual desktop on.
    ///
    /// - Throws: An error if `reg query` cannot be run.
    @MainActor
    static func isVirtualDesktopEnabled(bottle: Bottle) async throws -> Bool {
        try await virtualDesktopName(query: registryQuery(for: bottle)) != nil
    }

    /// The bottle's virtual desktop as its registry has it.
    ///
    /// - Returns: Whether the virtual desktop is on, and its size (such as
    ///   `"1920x1080"`) when the registry sets one.
    /// - Throws: An error if `reg query` cannot be run.
    @MainActor
    static func virtualDesktop(bottle: Bottle) async throws -> (enabled: Bool, resolution: String?) {
        try await virtualDesktop(query: registryQuery(for: bottle))
    }

    /// ``virtualDesktop(bottle:)`` over any registry, so the decision is
    /// testable without Wine.
    @MainActor
    internal static func virtualDesktop(
        query: RegistryStringQuery
    ) async throws -> (enabled: Bool, resolution: String?) {
        guard let name = try await virtualDesktopName(query: query) else {
            return (false, nil)
        }
        let resolution = try await query(VirtualDesktopRegistryKey.desktops.rawValue, name)
        return (true, resolution)
    }

    /// The name of the virtual desktop the registry turns on, or `nil` without one.
    @MainActor
    internal static func virtualDesktopName(query: RegistryStringQuery) async throws -> String? {
        let desktop = try await query(VirtualDesktopRegistryKey.explorer.rawValue, "Desktop")
        return desktop.flatMap { namesVirtualDesktop($0) ? $0 : nil }
    }

    /// String values read with `reg query`, without a log file: these are
    /// polls whose output is parsed, and a log file each would bury the
    /// launch logs.
    @MainActor
    private static func registryQuery(for bottle: Bottle) -> RegistryStringQuery {
        { key, name in
            let output = try await runWineWithBottle(
                ["reg", "query", key, "-v", name], bottle: bottle, createsLogFile: false
            )
            return registryValue(fromQueryOutput: output, type: .string)
        }
    }

    /// Whether a `Desktop` value names a virtual desktop: `root` is Wine's
    /// name for the desktop without one.
    internal static func namesVirtualDesktop(_ desktop: String) -> Bool {
        !desktop.isEmpty && desktop.caseInsensitiveCompare("root") != .orderedSame
    }
}
