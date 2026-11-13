//
//  GameConfigBackendAvailabilityTests.swift
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

private let concreteBackends: [GraphicsBackend] = [.d3dMetal, .dxmt, .dxvk, .wined3d]

/// A GameDB variant names a backend; the applicator must not set one this
/// machine can't run, or the bottle falls back to WineD3D at launch (#146).
@Suite("Game configuration backend availability")
@MainActor
struct GameConfigBackendAvailabilityTests {
    private func makeBottle() throws -> Bottle {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "GameConfigBackendAvailability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try BottleSettings().encode(to: url.appending(path: "Metadata.plist"))
        return Bottle(bottleUrl: url)
    }

    private func variant(_ backend: GraphicsBackend) -> GameConfigVariant {
        GameConfigVariant(
            id: "default", label: "Default", isDefault: true,
            settings: GameConfigVariantSettings(graphicsBackend: backend, dxvk: false)
        )
    }

    private func entry(_ variant: GameConfigVariant) -> GameDBEntry {
        GameDBEntry(id: "test-game", title: "Test Game", rating: .playable, variants: [variant])
    }

    @Test("An available backend is applied as written", arguments: concreteBackends)
    func availableBackendApplies(_ backend: GraphicsBackend) throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }

        _ = try GameConfigApplicator.apply(
            entry: entry(variant(backend)), variant: variant(backend), to: bottle,
            isBackendAvailable: { _ in true }
        )

        #expect(bottle.settings.graphicsBackend == backend)
    }

    @Test("A backend this machine can't run becomes Recommended", arguments: [GraphicsBackend.d3dMetal, .dxmt])
    func unavailableBackendBecomesRecommended(_ backend: GraphicsBackend) throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.settings.graphicsBackend = .dxvk
        let missing: (GraphicsBackend) -> Bool = { $0 != backend }

        _ = try GameConfigApplicator.apply(
            entry: entry(variant(backend)), variant: variant(backend), to: bottle,
            isBackendAvailable: missing
        )

        #expect(bottle.settings.graphicsBackend == .recommended)
    }

    @Test("The preview shows the backend that will be applied")
    func previewMatchesApply() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.settings.graphicsBackend = .dxvk
        let noD3DMetal: (GraphicsBackend) -> Bool = { $0 != .d3dMetal }

        let changes = GameConfigApplicator.previewChanges(
            variant: variant(.d3dMetal), bottle: bottle, isBackendAvailable: noD3DMetal
        )
        let row = try #require(changes.first { $0.settingName == "Graphics Backend" })
        #expect(row.newValue == GraphicsBackend.recommended.displayName)

        // A bottle already on Recommended has nothing to change.
        bottle.settings.graphicsBackend = .recommended
        let unchanged = GameConfigApplicator.previewChanges(
            variant: variant(.d3dMetal), bottle: bottle, isBackendAvailable: noD3DMetal
        )
        #expect(!unchanged.contains { $0.settingName == "Graphics Backend" })
    }

    @Test("Recommended passes through whatever is installed")
    func recommendedPassesThrough() {
        #expect(GameConfigApplicator.effectiveBackend(.recommended, isBackendAvailable: { _ in false }) == .recommended)
    }
}
