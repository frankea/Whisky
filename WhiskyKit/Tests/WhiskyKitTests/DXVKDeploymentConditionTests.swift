//
//  DXVKDeploymentConditionTests.swift
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

@testable import WhiskyKit
import XCTest

final class DXVKDeploymentConditionTests: XCTestCase {
    // MARK: - Wine.deploysDXVK

    private func deploys(
        backend: GraphicsBackend,
        legacy: Bool = false,
        descendantPlan: Bool = false,
        autoEnable: Bool = false,
        launcher: LauncherType? = nil
    ) -> Bool {
        Wine.deploysDXVK(
            effectiveBackend: backend,
            legacyProgramDXVK: legacy,
            launcherCarriesDescendantPlan: descendantPlan,
            autoEnableDXVK: autoEnable,
            detectedLauncher: launcher
        )
    }

    func testDXVKBackendDeploys() {
        XCTAssertTrue(deploys(backend: .dxvk))
    }

    func testOtherBackendsAloneDoNotDeploy() {
        for backend in [GraphicsBackend.d3dMetal, .dxmt, .wined3d] {
            XCTAssertFalse(deploys(backend: backend), "\(backend)")
        }
    }

    func testLegacyProgramFlagDeploys() {
        XCTAssertTrue(deploys(backend: .d3dMetal, legacy: true))
    }

    func testLauncherCarryingAGamePlanDeploys() {
        XCTAssertTrue(deploys(backend: .d3dMetal, descendantPlan: true))
    }

    func testAutoEnableDeploysOnlyForALauncherThatRequiresDXVK() {
        XCTAssertTrue(deploys(backend: .d3dMetal, autoEnable: true, launcher: .rockstar))
        XCTAssertFalse(deploys(backend: .d3dMetal, autoEnable: true, launcher: .steam))
        XCTAssertFalse(deploys(backend: .d3dMetal, autoEnable: true, launcher: nil))
        XCTAssertFalse(deploys(backend: .d3dMetal, autoEnable: false, launcher: .rockstar))
    }

    // MARK: - BottleSettings.deploysDXVK(whenLaunching:)

    func testRecommendedBackendSteersTheRockstarLauncherToDXVK() {
        var settings = BottleSettings()
        settings.graphicsBackend = .recommended
        settings.autoEnableDXVK = false
        // The legacy accessor says no, which is what the old warning read.
        XCTAssertFalse(settings.dxvk)
        XCTAssertTrue(settings.deploysDXVK(whenLaunching: .rockstar))
    }

    func testExplicitDXVKBackendDeploys() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        settings.autoEnableDXVK = false
        XCTAssertTrue(settings.deploysDXVK(whenLaunching: .rockstar))
    }

    func testAutoEnableDeploysUnderAnotherBackendForTheDetectedLauncher() {
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal
        settings.autoEnableDXVK = true
        settings.detectedLauncher = .rockstar
        XCTAssertTrue(settings.deploysDXVK(whenLaunching: .rockstar))
    }

    func testExplicitOtherBackendWithoutAutoEnableDoesNotDeploy() {
        var settings = BottleSettings()
        settings.graphicsBackend = .d3dMetal
        settings.autoEnableDXVK = false
        settings.detectedLauncher = .rockstar
        XCTAssertFalse(settings.deploysDXVK(whenLaunching: .rockstar))
    }

    func testAutoEnableNeedsTheDetectedLauncherToRequireDXVK() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt
        settings.autoEnableDXVK = true
        settings.detectedLauncher = .steam
        XCTAssertFalse(settings.deploysDXVK(whenLaunching: .rockstar))
    }
}
