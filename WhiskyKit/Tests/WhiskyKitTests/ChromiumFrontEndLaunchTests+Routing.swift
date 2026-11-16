//
//  ChromiumFrontEndLaunchTests+Routing.swift
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

/// A program-level Recommended in an explicit bottle, the MetalFX placeholder,
/// and a bottle whose games resolve to DXMT.
extension ChromiumFrontEndLaunchTests {
    // MARK: - Program-level Recommended in an explicit bottle

    @Test("A front end set to Recommended in a D3DMetal bottle gets DXVK however it starts")
    func programRecommendedRoutesTheSameEverywhere() async throws {
        let install = try installSteam3DMark()
        let frontEnd = install.appending(path: "bin/x64/3DMark.exe")
        let bottle = makeBottle(.d3dMetal)
        Program(url: frontEnd, bottle: bottle, peFile: nil).settings.overrides = backend(.recommended)

        let direct = ScopeRecorder()
        _ = try await prepare(frontEnd, in: bottle, programOverrides: backend(.recommended), recorder: direct)
        expectDXVK(direct.overrides(for: .program("3DMark.exe")), "direct launch")

        let steam = ScopeRecorder()
        try await steamLaunch(bottle, install: install, recorder: steam)
        expectDXVK(steam.overrides(for: .program("3DMark.exe")), "Steam launch")
        expectNotDXVK(steam.overrides(for: .program("TimeSpy.exe")), "TimeSpy.exe")

        try touch(["windows/notepad.exe"], in: bottleURL.appending(path: "drive_c"))
        let ahead = ScopeRecorder()
        _ = try await prepare(bottleURL.appending(path: "drive_c/windows/notepad.exe"), in: bottle, recorder: ahead)
        expectDXVK(ahead.overrides(for: .program("3DMark.exe")), "ahead of time")
        expectNotDXVK(ahead.overrides(for: .bottle), "the bottle scope")
    }

    // MARK: - MetalFX

    @Test("Launching 3DMark leaves the MetalFX placeholder its D3DMetal benchmarks need")
    func frontEndLaunchKeepsMetalFXPlaceholder() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        bottle.settings.metalFX = true
        let placeholder = bottleURL.appending(path: "drive_c/windows/system32")
            .appending(path: GPTKImporter.metalFXBridgeName)
        // Builtin-marked, the kind the launch removes when it clears.
        var stub = Data(count: 0x40)
        stub.append(Data("Wine builtin DLL".utf8))
        try stub.write(to: placeholder)

        _ = try await prepare(install.appending(path: "bin/x64/3DMark.exe"), in: bottle, recorder: ScopeRecorder())

        #expect(dxvkDeployed, "the front end itself runs on DXVK")
        #expect(FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)))
    }

    // MARK: - DXMT

    @Test("Without GPTK, 3DMark still gets DXVK and the bottle scope keeps DXMT")
    func dxmtBottleSteersTheFrontEnd() async throws {
        let install = try installSteam3DMark()
        let bottle = makeBottle()
        let recorder = ScopeRecorder()

        _ = try await prepare(
            install.appending(path: "bin/x64/3DMark.exe"), in: bottle, recommendedBackend: .dxmt, recorder: recorder
        )

        let entry = recorder.overrides(for: .program("3DMark.exe"))
        expectDXVK(entry, "3DMark.exe")
        #expect(entry?["d3d9"] == "n,b", "DXVK's d3d9, which DXMT does not ship")
        let bottleScope = recorder.overrides(for: .bottle)
        #expect(bottleScope?["winemetal"] == "b", "the bottle scope is DXMT's")
        #expect(bottleScope?["d3d9"] != "n,b", "the bottle scope is not DXVK's")
        #expect(dxvkDeployed)
    }

    @Test("On DXMT the steered rationale adds the shared-files caveat, and only there")
    func dxmtRationaleAddsTheCaveat() throws {
        let frontEnd = try #require(ChromiumFrontEnd.all.first)
        let steerings: [DXVKSteering] = [.chromiumFrontEnd(frontEnd), .launcher(.steam)]
        let caveat = String(localized: "config.graphics.backend.recommended.dxmtCaveat")
        for steering in steerings {
            let resolution = BackendResolution(backend: .dxvk, reason: .steered(steering))
            let onDXMT = resolution.rationale(gamesBackend: .dxmt)
            let onD3DMetal = resolution.rationale(gamesBackend: .d3dMetal)
            #expect(onDXMT.hasSuffix(" " + caveat), "\(steering.evidence)")
            #expect(!onD3DMetal.contains(caveat), "\(steering.evidence)")
        }
    }
}
