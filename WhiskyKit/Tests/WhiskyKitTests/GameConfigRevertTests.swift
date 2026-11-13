//
//  GameConfigRevertTests.swift
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
import Testing
@testable import WhiskyKit

/// What reverting an applied game configuration puts back in the bottle's
/// programs, and what it leaves alone.
@Suite("Game configuration revert: program settings")
@MainActor
final class GameConfigRevertTests {
    private let bottleURL: URL
    private let bottle: Bottle

    init() throws {
        bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "GameConfigRevertTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        try BottleSettings().encode(to: bottleURL.appending(path: "Metadata.plist"))
        bottle = Bottle(bottleUrl: bottleURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: bottleURL)
    }

    private func makeProgram(_ relativePath: String) throws -> Program {
        let url = bottle.url.appending(path: "drive_c").appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: url)
        let program = Program(url: url, bottle: bottle, peFile: nil)
        bottle.programs.append(program)
        return program
    }

    private func makeVariant(
        environment: [String: String]? = nil,
        verbs: [String]? = nil
    ) -> GameConfigVariant {
        GameConfigVariant(
            id: "recommended",
            label: "Recommended",
            isDefault: true,
            settings: GameConfigVariantSettings(),
            environmentVariables: environment,
            winetricksVerbs: verbs
        )
    }

    private func makeEntry(variant: GameConfigVariant) -> GameDBEntry {
        GameDBEntry(
            id: "test-game", title: "Test Game", rating: .playable, exeNames: ["TestGame.exe"], variants: [variant]
        )
    }

    @Test("Revert leaves program settings the apply did not set, including later edits")
    func revertKeepsOtherProgramSettings() throws {
        let game = try makeProgram("Games/Test/TestGame.exe")
        game.settings.environment = ["KEEP": "1", "DXVK_HUD": "0"]
        let variant = makeVariant(environment: ["DXVK_ASYNC": "1", "DXVK_HUD": "1"])
        let snapshot = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle
        )

        // Changed after the apply: kept by the revert.
        game.settings.arguments = "-dx11"
        game.settings.environment["DXVK_ASYNC"] = "0"
        game.settings.environment["NEW"] = "1"

        _ = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
        #expect(game.settings.arguments == "-dx11")
        #expect(game.settings.environment == ["KEEP": "1", "DXVK_HUD": "0", "DXVK_ASYNC": "0", "NEW": "1"])
    }

    @Test("A configuration without variables leaves the game's program out of the snapshot")
    func noVariablesNoProgramSnapshot() throws {
        let game = try makeProgram("Games/Test/TestGame.exe")
        let variant = makeVariant(verbs: ["vcrun2022"])
        let snapshot = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle, programURL: game.url
        )
        #expect(snapshot.programEnvironments == nil)

        game.settings.arguments = "-windowed"
        game.settings.environment = ["MINE": "1"]
        _ = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
        #expect(game.settings.arguments == "-windowed")
        #expect(game.settings.environment == ["MINE": "1"])
    }

    @Test("Revert does not restore whole program settings recorded by earlier versions")
    func revertIgnoresLegacyProgramSettings() throws {
        let game = try makeProgram("Games/Test/TestGame.exe")
        let legacy = try PropertyListEncoder().encode(ProgramSettings())
        let snapshot = try GameConfigSnapshot(
            bottleSettingsData: PropertyListEncoder().encode(bottle.settings),
            programSettingsData: [game.url.absoluteString: legacy],
            appliedEntryId: "test-game",
            appliedVariantId: "recommended"
        )
        try GameConfigSnapshot.save(snapshot, to: bottle.url)
        game.settings.arguments = "-novid"

        _ = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
        #expect(game.settings.arguments == "-novid")
    }

    @Test("Snapshots written before program environments were recorded still decode")
    func snapshotDecodesWithoutProgramEnvironments() throws {
        let snapshot = GameConfigSnapshot(appliedEntryId: "game", appliedVariantId: "recommended")
        let data = try PropertyListEncoder().encode(snapshot)
        let decoded = try PropertyListDecoder().decode(GameConfigSnapshot.self, from: data)
        #expect(decoded.programEnvironments == nil)

        let record = GameConfigProgramEnvironment(applying: ["A": "2", "B": "1"], to: ["A": "1", "C": "1"])
        #expect(record.previousValues == ["A": "1"])
        #expect(record.reverting(["A": "2", "B": "1", "C": "1"]) == ["A": "1", "C": "1"])
    }
}
