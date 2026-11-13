//
//  GameConfigApplyComponentsTests.swift
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

/// What applying a game configuration does beyond bottle settings: its
/// environment variables, the record of installed components, and how the
/// component installs are summarised.
@Suite("Game configuration apply: environment and components")
@MainActor
final class GameConfigApplyComponentsTests {
    private let bottleURL: URL
    private let bottle: Bottle

    init() throws {
        bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "GameConfigApplyComponentsTests-\(UUID().uuidString)")
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

    private func makeEntry(
        id: String = "test-game",
        exeNames: [String]? = ["TestGame.exe"],
        variant: GameConfigVariant
    ) -> GameDBEntry {
        GameDBEntry(id: id, title: "Test Game", rating: .playable, exeNames: exeNames, variants: [variant])
    }

    // MARK: - Environment Variables

    @Test("Variables go into the settings of the game's program, matched by name without case")
    func environmentGoesToMatchingProgram() throws {
        let game = try makeProgram("Games/Test/testgame.exe")
        let other = try makeProgram("Games/Other/Other.exe")
        game.settings.environment = ["KEEP": "1", "D3DM_SUPPORT_DXR": "1"]
        let variant = makeVariant(environment: ["D3DM_SUPPORT_DXR": "0"])

        let snapshot = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle
        )

        #expect(game.settings.environment == ["KEEP": "1", "D3DM_SUPPORT_DXR": "0"])
        #expect(other.settings.environment.isEmpty)
        #expect(bottle.settings.gameConfigEnvironments.isEmpty)
        #expect(snapshot.programSettingsData?.keys.sorted() == [game.url.absoluteString])
    }

    @Test("The program the configuration is applied from gets the variables")
    func environmentGoesToTheApplyingProgram() throws {
        let launcher = try makeProgram("Games/Test/Launcher.exe")
        let game = try makeProgram("Games/Test/TestGame.exe")
        let variant = makeVariant(environment: ["PULSE_LATENCY_MSEC": "60"])

        _ = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle, programURL: launcher.url
        )

        #expect(launcher.settings.environment == ["PULSE_LATENCY_MSEC": "60"])
        #expect(game.settings.environment.isEmpty)
    }

    @Test("Revert puts the program's environment back, even once the bottle no longer lists it")
    func revertRestoresProgramEnvironment() throws {
        let game = try makeProgram("Games/Test/TestGame.exe")
        game.settings.environment = ["KEEP": "1"]
        let variant = makeVariant(environment: ["DXVK_ASYNC": "1"])
        let snapshot = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle
        )
        #expect(game.settings.environment["DXVK_ASYNC"] == "1")

        _ = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
        #expect(game.settings.environment == ["KEEP": "1"])

        // Applied again, then reverted with the program gone from the list:
        // the settings file is still put back.
        let again = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle
        )
        bottle.programs.removeAll()
        _ = try GameConfigApplicator.revert(bottle: bottle, snapshot: again)
        #expect(Program(url: game.url, bottle: bottle, peFile: nil).settings.environment == ["KEEP": "1"])
    }

    @Test("Without the game in the bottle, the variables are kept in the bottle, scoped to its executables")
    func environmentFallsBackToBottleRecord() throws {
        let variant = makeVariant(environment: ["WINE_LARGE_ADDRESS_AWARE": "1"])
        let entry = makeEntry(variant: variant)

        let snapshot = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        #expect(bottle.settings.gameConfigEnvironments == [GameConfigEnvironment(
            entryId: "test-game", title: "Test Game", executables: ["TestGame.exe"],
            variables: ["WINE_LARGE_ADDRESS_AWARE": "1"]
        )])
        #expect(bottle.settings.gameConfigEnvironment(forExecutable: "testgame.EXE")
            == ["WINE_LARGE_ADDRESS_AWARE": "1"])
        #expect(bottle.settings.gameConfigEnvironment(forExecutable: "Other.exe").isEmpty)

        // Applying the entry again replaces its record rather than adding one.
        _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)
        #expect(bottle.settings.gameConfigEnvironments.count == 1)

        _ = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
        #expect(bottle.settings.gameConfigEnvironments.isEmpty)
    }

    @Test("A bottle record also covers the program the configuration was applied from")
    func bottleRecordIncludesApplyingProgram() throws {
        let variant = makeVariant(environment: ["A": "1"])
        let programURL = bottle.url.appending(path: "drive_c/Games/Launch.exe")

        _ = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle, programURL: programURL
        )

        #expect(bottle.settings.gameConfigEnvironments.first?.executables == ["TestGame.exe", "Launch.exe"])
    }

    @Test("Records without executables cover every launch, and a later record wins")
    func bottleRecordScoping() {
        var settings = BottleSettings()
        settings.gameConfigEnvironments = [
            GameConfigEnvironment(entryId: "any", title: "Any", executables: [], variables: ["A": "1", "B": "1"]),
            GameConfigEnvironment(entryId: "game", title: "Game", executables: ["Game.exe"], variables: ["B": "2"])
        ]

        #expect(settings.gameConfigEnvironment(forExecutable: "Game.exe") == ["A": "1", "B": "2"])
        #expect(settings.gameConfigEnvironment(forExecutable: "Tool.exe") == ["A": "1", "B": "1"])
    }

    @Test("Bottle records survive a settings round trip, and older settings decode without them")
    func bottleRecordPersistence() throws {
        var settings = BottleSettings()
        settings.gameConfigEnvironments = [
            GameConfigEnvironment(entryId: "game", title: "Game", executables: ["Game.exe"], variables: ["A": "1"])
        ]
        let data = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)
        #expect(decoded.gameConfigEnvironments == settings.gameConfigEnvironments)

        // Settings written before the field existed have no key for it.
        var plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist.removeValue(forKey: "gameConfigEnvironments") != nil)
        let legacyData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let legacy = try PropertyListDecoder().decode(BottleSettings.self, from: legacyData)
        #expect(legacy.gameConfigEnvironments.isEmpty)
    }

    @Test("A bottle record's variables reach launches of its game only, under a launch plan's own")
    func bottleRecordReachesLaunches() async throws {
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        bottle.settings.gameConfigEnvironments = [GameConfigEnvironment(
            entryId: "game", title: "Game", executables: ["Game.exe"],
            variables: ["D3DM_SUPPORT_DXR": "0", "SHARED": "record"]
        )]
        let game = try makeProgram("Games/Game/game.exe").url
        let tool = try makeProgram("Games/Tool.exe").url
        let noWrites: Wine.DLLOverrideWriter = { _, _ in }
        let noImports: Wine.RegistryImporter = { _, _ in }

        let gameLaunch = try await Wine.prepareProgramLaunch(
            at: game, bottle: bottle, gameProfileEnvironment: ["SHARED": "plan"],
            overrideWriter: noWrites, importer: noImports
        )
        let toolLaunch = try await Wine.prepareProgramLaunch(
            at: tool, bottle: bottle, overrideWriter: noWrites, importer: noImports
        )

        #expect(gameLaunch.environment["D3DM_SUPPORT_DXR"] == "0")
        #expect(gameLaunch.environment["SHARED"] == "plan")
        #expect(toolLaunch.environment["D3DM_SUPPORT_DXR"] == nil)
    }

    // MARK: - Preview

    @Test("The preview compares variables against where the apply puts them")
    func previewComparesEnvironment() throws {
        let game = try makeProgram("Games/Test/TestGame.exe")
        game.settings.environment = ["SAME": "1", "DIFFERENT": "old"]
        let variant = makeVariant(environment: ["SAME": "1", "DIFFERENT": "new", "NEW": "x"])

        let changes = GameConfigApplicator.previewChanges(
            variant: variant, bottle: bottle, entry: makeEntry(variant: variant)
        ).filter { $0.kind == .environmentVariable }

        #expect(changes.map(\.settingName) == ["DIFFERENT", "NEW"])
        #expect(changes.first?.currentValue == "old")
        #expect(changes.last?.currentValue == String(localized: "gameConfig.preview.value.notSet"))
    }

    @Test("Without an entry, every variable is previewed as not set")
    func previewWithoutEntry() {
        let variant = makeVariant(environment: ["A": "1", "B": "2"])

        let changes = GameConfigApplicator.previewChanges(variant: variant, bottle: bottle)
            .filter { $0.kind == .environmentVariable }

        #expect(changes.map(\.settingName) == ["A", "B"])
    }

    @Test("The preview leaves out a bottle record's variables already set")
    func previewAgainstBottleRecord() throws {
        let variant = makeVariant(environment: ["A": "1"])
        let entry = makeEntry(variant: variant)
        _ = try GameConfigApplicator.apply(entry: entry, variant: variant, to: bottle)

        let changes = GameConfigApplicator.previewChanges(variant: variant, bottle: bottle, entry: entry)

        #expect(!changes.contains { $0.kind == .environmentVariable })
    }

    @Test("The preview only lists the verbs that are not installed")
    func previewSkipsInstalledVerbs() {
        let variant = makeVariant(verbs: ["vcrun2022", "d3dcompiler_47"])

        let changes = GameConfigApplicator.previewChanges(
            variant: variant, bottle: bottle, installedVerbs: ["vcrun2022"]
        )

        #expect(changes.filter { $0.kind == .winetricksVerb }.map(\.settingName) == ["d3dcompiler_47"])
    }

    // MARK: - Installed Verbs

    @Test("Apply records no verbs; the ones that install are added to the snapshot")
    func installedVerbsAreRecorded() throws {
        let variant = makeVariant(verbs: ["vcrun2022", "dotnet48"])
        let snapshot = try GameConfigApplicator.apply(
            entry: makeEntry(variant: variant), variant: variant, to: bottle
        )
        #expect(snapshot.installedVerbs == nil)

        try GameConfigApplicator.recordInstalledVerbs(["vcrun2022"], bottleURL: bottle.url)
        try GameConfigApplicator.recordInstalledVerbs(["vcrun2022", "dotnet48"], bottleURL: bottle.url)

        let saved = try #require(GameConfigSnapshot.load(from: bottle.url))
        #expect(saved.installedVerbs == ["vcrun2022", "dotnet48"])
        #expect(try GameConfigApplicator.revert(bottle: bottle, snapshot: saved) == ["vcrun2022", "dotnet48"])
    }

    @Test("Recording verbs without a snapshot does nothing")
    func recordingWithoutSnapshot() throws {
        try GameConfigApplicator.recordInstalledVerbs(["vcrun2022"], bottleURL: bottle.url)
        #expect(GameConfigSnapshot.load(from: bottle.url) == nil)
    }

    // MARK: - Program Match

    @Test("A program is matched to its entry's default variant")
    func recommendedConfigurationForProgram() throws {
        let program = try makeProgram("Games/Test/TestGame.exe")
        let variant = makeVariant(environment: ["A": "1"])
        let entry = makeEntry(variant: variant)

        let config = GameConfigApplicator.recommendedConfiguration(for: program, entries: [entry])

        #expect(config?.entry == entry)
        #expect(config?.variant == variant)
        #expect(GameConfigApplicator.recommendedConfiguration(for: program, entries: []) == nil)
    }
}

// MARK: - Verb Install Outcome

@Suite("Game configuration component install outcome")
struct GameConfigVerbInstallOutcomeTests {
    @Test("Only a run where every verb installed is complete")
    func complete() {
        var outcome = GameConfigVerbInstallOutcome(requested: ["a", "b"])
        outcome.record("a", exitCode: 0, failure: nil)
        #expect(outcome.status == .incomplete)
        outcome.record("b", exitCode: 0, failure: nil)
        #expect(outcome.status == .complete)
        #expect(outcome.installed == ["a", "b"])
        #expect(outcome.missing.isEmpty)
    }

    @Test("Nothing to install is complete")
    func nothingRequested() {
        #expect(GameConfigVerbInstallOutcome(requested: []).status == .complete)
    }

    @Test("A failed verb fails the run, and is listed before the ones never attempted")
    func failed() {
        var outcome = GameConfigVerbInstallOutcome(requested: ["a", "b", "c"])
        outcome.record("a", exitCode: 0, failure: nil)
        outcome.record("b", exitCode: 1, failure: nil)
        #expect(outcome.status == .failed)
        #expect(outcome.failed == ["b"])
        #expect(outcome.notAttempted == ["c"])
        #expect(outcome.missing == ["b", "c"])
    }

    @Test("Verbs never attempted leave the run incomplete")
    func incomplete() {
        let outcome = GameConfigVerbInstallOutcome(requested: ["a", "b"])
        #expect(outcome.status == .incomplete)
        #expect(outcome.missing == ["a", "b"])
    }

    @Test("A run that reported an error or no exit code did not install its verb")
    func succeeded() {
        #expect(GameConfigVerbInstallOutcome.succeeded(exitCode: 0, failure: nil))
        #expect(!GameConfigVerbInstallOutcome.succeeded(exitCode: 0, failure: "Missing cabextract resource"))
        #expect(!GameConfigVerbInstallOutcome.succeeded(exitCode: nil, failure: nil))
        #expect(!GameConfigVerbInstallOutcome.succeeded(exitCode: 15, failure: nil))
    }

    @Test("Duplicates, unknown verbs and second records are ignored")
    func recordingRules() {
        var outcome = GameConfigVerbInstallOutcome(requested: ["a", "a", "b"])
        #expect(outcome.requested == ["a", "b"])
        outcome.record("z", exitCode: 0, failure: nil)
        outcome.record("a", exitCode: 1, failure: nil)
        outcome.record("a", exitCode: 0, failure: nil)
        #expect(outcome.installed.isEmpty)
        #expect(outcome.failed == ["a"])
    }
}
