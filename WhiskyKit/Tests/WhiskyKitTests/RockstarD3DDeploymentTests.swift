//
//  RockstarD3DDeploymentTests.swift
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

/// What a DXVK launch writes for the Rockstar Games Launcher's swapped
/// layout, in which order, and how it takes it back (#382).
@Suite("Rockstar Direct3D swap deployment")
@MainActor
final class RockstarD3DDeploymentTests {
    private let fixture: RockstarD3DFixture
    private let root: URL

    init() throws {
        fixture = try RockstarD3DFixture(prefix: "rockstar_deploy")
        root = fixture.root
        try fixture.installRockstar(socialClub: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Every copy folder of this fixture's bottle.
    private var copyFolders: [URL] {
        (RockstarD3DFixture.steamCopyKeys + [RockstarD3DFixture.socialClubKey]).map {
            fixture.driveC.appending(path: $0)
        }
    }

    private func expectSwapped(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(
            Wine.isStrippedCopy(fixture.system32("d3d11.dll"), of: fixture.d3d11Source),
            sourceLocation: sourceLocation
        )
        #expect(
            Wine.isStrippedCopy(fixture.system32("dxgi.dll"), of: fixture.dxgiSource),
            sourceLocation: sourceLocation
        )
        #expect(
            RockstarD3DFixture.contents(fixture.system32("d3d10core.dll"))
                == RockstarD3DFixture.dxvkBytes("x64", "d3d10core.dll"),
            sourceLocation: sourceLocation
        )
        for folder in copyFolders {
            #expect(
                RockstarD3DFixture.holdsDXVKCopies(folder),
                "\(folder.lastPathComponent)",
                sourceLocation: sourceLocation
            )
        }
    }

    private func expectTornDown(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(
            RockstarD3DFixture.contents(fixture.system32("d3d11.dll"))
                == RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll"),
            sourceLocation: sourceLocation
        )
        for folder in copyFolders {
            #expect(
                RockstarD3DFixture.holdsNoCopies(folder),
                "\(folder.lastPathComponent)",
                sourceLocation: sourceLocation
            )
        }
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url), sourceLocation: sourceLocation)
    }

    // MARK: - Swap

    @Test("A fresh swap records first, places the copies, deploys DXVK around Wine's d3d11, and records last")
    func freshSwapOrder() throws {
        let recorder = RockstarOpsRecorder()

        let layout = try fixture.startSteam(ops: recorder.ops)

        #expect(layout == .swapped(source: fixture.d3d11Source))
        #expect(recorder.log == [
            "saveRecord(interim)", "createFolder Social Club",
            "installCopy cef.win64", "installCopy cef.win64", "installCopy cef.win7x64", "installCopy cef.win7x64",
            "installCopy Steam", "installCopy Steam", "installCopy Social Club", "installCopy Social Club",
            "enableDXVK(source)", "dxgi", "saveRecord(final)"
        ])
        // Wine's d3d11 was in its slot before dxgi was reconciled.
        #expect(recorder.d3d11StrippedAtDXGI == true)
        expectSwapped()
        #expect(RockstarD3DFixture.contents(fixture.syswow64("d3d11.dll"))
            == RockstarD3DFixture.dxvkBytes("x32", "d3d11.dll"))
        #expect(RockstarD3DFixture.holdsNoCopies(fixture.steamRoot.appending(path: "bin/cef/cef.win7")))
        let record = try #require(fixture.record)
        #expect(record.copies.count == 8)
        #expect(record.createdFolders == [RockstarD3DFixture.socialClubKey])
        #expect(record.engineStamp == "4.8.3")
        #expect(record.sourceSHA256 == RockstarD3DLayoutRecord.sha256(of: fixture.d3d11Source))
        #expect(record.system32D3D11 == RockstarD3DLayoutRecord.sha256(of: fixture.system32("d3d11.dll")))
        #expect(fixture.bottle.rockstarD3DLayout == layout)
    }

    @Test("A second launch rewrites none of the swap's files")
    func secondLaunchWritesNothing() throws {
        try fixture.startSteam()
        let files = copyFolders.flatMap { folder in Wine.rockstarD3DCopyDLLs.map { folder.appending(path: $0) } }
            + [fixture.system32("d3d11.dll"), RockstarD3DLayoutRecord.url(in: fixture.bottle.url)]
        let before = files.map(RockstarD3DFixture.identity)
        let recorder = RockstarOpsRecorder()

        let layout = try fixture.startSteam(ops: recorder.ops)

        #expect(layout == .swapped(source: fixture.d3d11Source))
        #expect(recorder.log == ["enableDXVK(source)", "dxgi"])
        #expect(files.map(RockstarD3DFixture.identity) == before)
    }

    @Test("Rockstar's own Launcher.exe keeps the layout, and a front end in a served folder does too")
    func launcherAndServedFrontEndKeepTheLayout() throws {
        let threeDMark = fixture.steamRoot.appending(path: "steamapps/common/3DMark/bin/x64/3DMark.exe")
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: threeDMark)
        try fixture.startSteam()

        for url in [fixture.rockstarLauncher, threeDMark] {
            let layout = try Wine.deployDXVK(bottle: fixture.bottle, from: fixture.dxvk, rockstar: fixture.launch(url))
            #expect(layout == .swapped(source: fixture.d3d11Source), "\(url.lastPathComponent)")
            expectSwapped()
        }
    }

    // MARK: - Teardown

    @Test("Turning the setting off puts DXVK back, takes the copies back and keeps the user's files")
    func toggleOffTearsDown() throws {
        try fixture.startSteam()
        let userFile = fixture.steamRoot.appending(path: "bin/cef/cef.win64/user.txt")
        try Data("mine".utf8).write(to: userFile)
        fixture.bottle.settings.rockstarWineD3D = false
        let recorder = RockstarOpsRecorder()

        let layout = try fixture.startSteam(ops: recorder.ops)

        #expect(layout == .degraded(.disabledByUser))
        #expect(recorder.log.first == "enableDXVK(nil)")
        #expect(recorder.log.filter { $0.hasPrefix("removeCopy") }.count == 8)
        #expect(recorder.log.suffix(2) == ["removeFolderIfEmpty Social Club", "removeRecord"])
        expectTornDown()
        #expect(RockstarD3DFixture.exists(userFile))
        #expect(!RockstarD3DFixture.exists(fixture.socialClub))
        #expect(RockstarD3DFixture.exists(fixture.rockstarLauncher))
    }

    @Test("A Social Club folder Rockstar's installer filled stays after the teardown")
    func filledSocialClubStays() throws {
        try fixture.startSteam()
        try fixture.installRockstar()
        fixture.bottle.settings.rockstarWineD3D = false

        try fixture.startSteam()

        expectTornDown()
        #expect(RockstarD3DFixture.exists(fixture.socialClub.appending(path: "SocialClubHelper.exe")))
    }

    @Test("Removing GPTK tears the swap down, as Rockstar's leaving the bottle does")
    func payloadOrRockstarGoneTearsDown() throws {
        try fixture.startSteam()
        let layout = try fixture.startSteam(payloadDeployed: false)
        #expect(layout == .builtin)
        expectTornDown()

        try fixture.startSteam()
        expectSwapped()
        try FileManager.default.removeItem(at: fixture.driveC.appending(path: "Program Files/Rockstar Games"))
        #expect(try fixture.startSteam() == nil)
        expectTornDown()
    }

    // MARK: - Failures

    @Test("A copy that cannot be placed leaves the bottle on DXVK with nothing of the swap left")
    func failedCopyPutsDXVKBack() throws {
        let recorder = RockstarOpsRecorder()
        recorder.failAt = "installCopy cef.win7x64"

        let layout = try fixture.startSteam(ops: recorder.ops)

        #expect(layout == .degraded(.swapFailed("injected")))
        #expect(!recorder.log.contains("enableDXVK(source)"))
        expectTornDown()
        #expect(!RockstarD3DFixture.exists(fixture.socialClub))
    }

    @Test("A dxgi.dll that could not be placed fails the swap")
    func failedDXGIFailsTheSwap() throws {
        let recorder = RockstarOpsRecorder()
        recorder.skipDXGI = true

        let layout = try fixture.startSteam(ops: recorder.ops)

        #expect(layout == .degraded(.swapFailed(RockstarD3DSwapError.notInPlace("dxgi.dll").localizedDescription)))
        expectTornDown()
    }

    // MARK: - Other launches

    @Test("Another DXVK launch suspends the swap for its session, and the next Steam start swaps again")
    func otherLaunchSuspends() throws {
        try fixture.startSteam()
        let other = fixture.driveC.appending(path: "Games/Other/Other.exe")
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: other)
        let recordBefore = fixture.record

        let layout = try Wine.deployDXVK(bottle: fixture.bottle, from: fixture.dxvk, rockstar: fixture.launch(other))

        #expect(layout == nil)
        #expect(RockstarD3DFixture.contents(fixture.system32("d3d11.dll"))
            == RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll"))
        #expect(fixture.record == recordBefore)
        #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsDXVKCopies($0) })

        #expect(try fixture.startSteam() == .swapped(source: fixture.d3d11Source))
        expectSwapped()
    }

    @Test("A launch on DXMT never touches the swap")
    func dxmtLaunchLeavesTheSwap() throws {
        try fixture.startSteam()
        let game = fixture.driveC.appending(path: "Games/DXMT/Game.exe")
        try fixture.write(PEBuilder.createMinimalPE32Plus(), to: game)
        let record = RockstarD3DLayoutRecord.url(in: fixture.bottle.url)
        let before = RockstarD3DFixture.identity(record)

        let layout = try Wine.deployLauncherAndGameLayers(
            bottle: fixture.bottle, effectiveBackend: .dxmt, programOverrides: nil,
            launcherCarriesDescendantPlan: false, gameExecutables: [game], dxvkFolder: fixture.dxvk,
            dxmtFolder: root.appending(path: "DXMT"), rockstar: fixture.launch(game)
        )

        #expect(layout == nil)
        #expect(RockstarD3DFixture.identity(record) == before)
        expectSwapped()
    }

    @Test("Without a launch to decide for, DXVK deploys exactly as before")
    func noRockstarLaunchIsTheLegacyPath() throws {
        let layout = try Wine.deployLauncherAndGameLayers(
            bottle: fixture.bottle, effectiveBackend: .dxvk, programOverrides: nil,
            launcherCarriesDescendantPlan: false, gameExecutables: [fixture.steamExe], dxvkFolder: fixture.dxvk,
            dxmtFolder: root.appending(path: "DXMT")
        )

        #expect(layout == nil)
        #expect(RockstarD3DFixture.contents(fixture.system32("d3d11.dll"))
            == RockstarD3DFixture.dxvkBytes("x64", "d3d11.dll"))
        #expect(!RockstarD3DLayoutRecord.exists(in: fixture.bottle.url))
        #expect(copyFolders.allSatisfy { RockstarD3DFixture.holdsNoCopies($0) })
    }
}
