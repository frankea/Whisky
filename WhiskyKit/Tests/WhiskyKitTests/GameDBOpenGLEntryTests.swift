//
//  GameDBOpenGLEntryTests.swift
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

/// The Binding of Isaac renders through OpenGL, which no graphics backend
/// setting reaches, so its configuration must not change the bottle's backend
/// for every other program in it (#200).
@Suite("OpenGL game configurations leave the backend alone")
@MainActor
struct GameDBOpenGLEntryTests {
    private func isaac() throws -> GameDBEntry {
        try #require(GameDBLoader.loadDefaults().first { $0.id == "binding-of-isaac-rebirth" })
    }

    @Test("Isaac's default variant sets no backend")
    func isaacSetsNoBackend() throws {
        let variant = try #require(isaac().defaultVariant)
        #expect(variant.settings.graphicsBackend == nil)
        // The legacy switch would reset the bottle to Recommended.
        #expect(variant.settings.dxvk == nil)
    }

    @Test("Applying Isaac keeps the bottle's backend", arguments: [GraphicsBackend.dxmt, .d3dMetal, .recommended])
    func applyKeepsBackend(_ backend: GraphicsBackend) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "GameDBOpenGL-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try BottleSettings().encode(to: url.appending(path: "Metadata.plist"))
        let bottle = Bottle(bottleUrl: url)
        bottle.settings.graphicsBackend = backend
        let entry = try isaac()
        let variant = try #require(entry.defaultVariant)

        #expect(!GameConfigApplicator.previewChanges(variant: variant, bottle: bottle)
            .contains { $0.category == "Graphics" && ["Graphics Backend", "DXVK"].contains($0.settingName) })
        _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        #expect(bottle.settings.graphicsBackend == backend)
    }
}
