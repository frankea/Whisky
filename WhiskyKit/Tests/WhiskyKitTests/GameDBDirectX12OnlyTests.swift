//
//  GameDBDirectX12OnlyTests.swift
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

import Testing
@testable import WhiskyKit

/// The bundled GameDB must never put a DirectX 12 only title on DXVK (#276).
///
/// DXVK translates Direct3D 9 to 11 only, and its preset turns d3d12 off beside
/// D3DMetal's builtin, so such a title cannot start on it. A game's plan now
/// reaches the game on every Steam launch, so a wrong recommendation breaks it.
@Suite("GameDB DirectX 12 only titles")
struct GameDBDirectX12OnlyTests {
    /// Entry IDs of titles with no Direct3D 9-11 renderer, per PCGamingWiki's
    /// API section (cross-checked against Steam's system requirements).
    /// Red Dead Redemption 2 also has Vulkan, but no path DXVK can render.
    static let directX12OnlyEntryIds: Set<String> = [
        "animal-well",
        "cyberpunk-2077",
        "horizon-forbidden-west",
        "horizon-zero-dawn",
        "jusant",
        "monster-hunter-wilds",
        "persona-3-reload",
        "red-dead-redemption-2",
        "starfield",
        "street-fighter-6",
        "talos-principle-2"
    ]

    @Test("Every listed DirectX 12 only title is still in the database")
    func allowlistMatchesTheDatabase() {
        let ids = Set(GameDBLoader.loadDefaults().map(\.id))
        let missing = Self.directX12OnlyEntryIds.subtracting(ids)
        #expect(missing.isEmpty, "Renamed or removed entries: \(missing.sorted())")
    }

    @Test("No variant of a DirectX 12 only title recommends DXVK")
    func noDirectX12OnlyTitleRecommendsDXVK() {
        let entries = GameDBLoader.loadDefaults().filter { Self.directX12OnlyEntryIds.contains($0.id) }
        for entry in entries {
            for variant in entry.variants {
                #expect(
                    variant.settings.graphicsBackend != .dxvk,
                    "\(entry.id) / \(variant.id) recommends the DXVK backend"
                )
                #expect(variant.settings.dxvk != true, "\(entry.id) / \(variant.id) turns DXVK on")
            }
        }
    }
}
