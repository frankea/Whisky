//
//  GameDBSteamEntryPlanTests.swift
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

import Testing
@testable import WhiskyKit

/// Bundled Steam entries, checked through the plan a Steam launch builds from
/// them, so a mistyped App ID or setting shows up here rather than at Play.
@Suite("GameDB Steam entries reach the launch plan")
struct GameDBSteamEntryPlanTests {
    private static func everyBackend(_: GraphicsBackend) -> Bool {
        true
    }

    @Test("Trine 4 launches on DXMT and changes nothing else")
    func trine4() {
        let plan = LaunchResolver.plan(steamAppId: 690_640, isBackendAvailable: Self.everyBackend)

        #expect(plan.overrides.graphicsBackend == .dxmt)
        #expect(plan.overrides.dxvkAsync == nil)
        #expect(plan.overrides.enhancedSync == nil)
        #expect(plan.gameExecutables == ["trine4_game.exe"])
        #expect(plan.launchArguments.isEmpty)
    }

    @Test("Screw Drivers launches on DXVK with async shaders and msync")
    func screwDrivers() {
        let plan = LaunchResolver.plan(steamAppId: 1_279_510, isBackendAvailable: Self.everyBackend)

        #expect(plan.overrides.graphicsBackend == .dxvk)
        #expect(plan.overrides.dxvkAsync == true)
        #expect(plan.overrides.enhancedSync == .msync)
        #expect(plan.gameProfileEnvironment.isEmpty)
        #expect(plan.gameExecutables == ["Screw Drivers.exe"])
    }

    @Test("BeamNG.drive launches on D3DMetal with its -nogfx switches after the App ID")
    func beamNG() {
        let plan = LaunchResolver.plan(steamAppId: 284_160, isBackendAvailable: Self.everyBackend)

        #expect(plan.overrides.graphicsBackend == .d3dMetal)
        #expect(plan.launchArguments == [
            "-nogfxgpudriven", "-nogfxgpuupload", "-nogfxbindless", "-nogfxbindlesscbv", "-nogfxindirectconstants"
        ])
        #expect(plan.gameExecutables == ["BeamNG.drive.x64.exe"])
    }

    @Test("BeamNG.drive falls back to Recommended without the GPTK payload, switches and all")
    func beamNGWithoutD3DMetal() {
        let plan = LaunchResolver.plan(steamAppId: 284_160, isBackendAvailable: { $0 != .d3dMetal })

        #expect(plan.overrides.graphicsBackend == .recommended)
        #expect(plan.launchArguments.count == 5)
    }
}
