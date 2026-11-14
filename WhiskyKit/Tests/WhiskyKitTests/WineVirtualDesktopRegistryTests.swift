//
//  WineVirtualDesktopRegistryTests.swift
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

@Suite("Wine Virtual Desktop Registry Tests")
@MainActor
struct WineVirtualDesktopRegistryTests {
    private static let explorer = #"HKCU\Software\Wine\Explorer"#
    private static let desktops = #"HKCU\Software\Wine\Explorer\Desktops"#

    /// A registry query over fixed values, keyed `key\name`.
    private func query(_ values: [String: String]) -> Wine.RegistryStringQuery {
        { key, name in values[key + #"\"# + name] }
    }

    @Test("A named desktop with a size reads as on, with that size")
    func namedDesktopWithSize() async throws {
        let registry = query([
            Self.explorer + #"\Desktop"#: "Default",
            Self.desktops + #"\Default"#: "1280x720"
        ])

        let desktop = try await Wine.virtualDesktop(query: registry)

        #expect(desktop.enabled)
        #expect(desktop.resolution == "1280x720")
    }

    @Test("A named desktop without a size reads as on, with no size")
    func namedDesktopWithoutSize() async throws {
        let desktop = try await Wine.virtualDesktop(query: query([Self.explorer + #"\Desktop"#: "Default"]))

        #expect(desktop.enabled)
        #expect(desktop.resolution == nil)
    }

    @Test("No Desktop value, an empty one, or root means no virtual desktop", arguments: [nil, "", "root", "ROOT"])
    func noVirtualDesktop(desktopValue: String?) async throws {
        var values: [String: String] = [Self.desktops + #"\root"#: "800x600"]
        if let desktopValue {
            values[Self.explorer + #"\Desktop"#] = desktopValue
        }

        let desktop = try await Wine.virtualDesktop(query: query(values))

        #expect(!desktop.enabled)
        #expect(desktop.resolution == nil)
        #expect(try await Wine.virtualDesktopName(query: query(values)) == nil)
    }

    @Test("A failing query is reported, not read as off")
    func failingQueryThrows() async {
        let failing: Wine.RegistryStringQuery = { _, _ in throw CocoaError(.fileReadUnknown) }

        await #expect(throws: CocoaError.self) {
            _ = try await Wine.virtualDesktop(query: failing)
        }
    }
}
