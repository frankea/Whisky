//
//  BackendResolverLauncherTests.swift
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

import SemanticVersion
@testable import WhiskyKit
import XCTest

final class BackendResolverLauncherTests: XCTestCase {
    /// The whole point: with D3DMetal installed a game gets it, because that is
    /// the reason to install it.
    func testGameGetsD3DMetalWhenInstalled() {
        let backend = GraphicsBackendResolver.resolve(for: nil, d3dMetalInstalled: true)
        XCTAssertEqual(backend, .d3dMetal)
    }

    /// And a launcher does not. Chromium cannot render on D3DMetal: the window
    /// comes up, the process tree looks healthy, nothing paints.
    func testLauncherGetsDXVKWhenD3DMetalIsInstalled() {
        for launcher in LauncherType.allCases {
            XCTAssertEqual(
                GraphicsBackendResolver.resolve(for: launcher, d3dMetalInstalled: true),
                .dxvk,
                "\(launcher.displayName) resolved to a backend its client cannot render on"
            )
        }
    }

    /// DXMT is just as unrenderable for Chromium as D3DMetal, so on a runtime
    /// that would recommend DXMT a launcher still gets DXVK. This is the
    /// payload-less default install: without the steer, the first Steam launch
    /// deploys DXMT and the client never shows a window.
    func testLauncherGetsDXVKWhenDXMTWouldBeRecommended() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: nil, runtimeInfo: runtime, d3dMetalInstalled: false, dxmtRuntimeNative: true
            ),
            .dxmt
        )
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: .steam, runtimeInfo: runtime, d3dMetalInstalled: false, dxmtRuntimeNative: true
            ),
            .dxvk
        )
    }

    /// With neither D3DMetal nor DXMT the answer is DXVK for everyone, so the
    /// steer changes nothing there.
    func testLauncherAndGameAgreeWhenOnlyDXVKExists() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 0, 0))
        let game = GraphicsBackendResolver.resolve(
            for: nil, runtimeInfo: runtime, d3dMetalInstalled: false
        )
        let launcher = GraphicsBackendResolver.resolve(
            for: .steam, runtimeInfo: runtime, d3dMetalInstalled: false
        )
        XCTAssertEqual(game, .dxvk)
        XCTAssertEqual(game, launcher)
    }

    /// Callers that pass nothing keep the old behaviour, so every existing
    /// call site is unaffected.
    func testDefaultArgumentMatchesTheGameCase() {
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(d3dMetalInstalled: true),
            GraphicsBackendResolver.resolve(for: nil, d3dMetalInstalled: true)
        )
    }

    /// A game inside a Steam library is not the Steam client, so it must not
    /// be steered onto DXVK.
    func testSteamLibraryGameResolvesAsAGame() {
        let url = URL(filePath: "/B/Steam/steamapps/common/Some Game/game.exe")
        XCTAssertNil(LauncherType.detect(from: url))
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: LauncherType.detect(from: url), d3dMetalInstalled: true
            ),
            .d3dMetal
        )
    }

    func testSteamClientResolvesAsALauncher() {
        let url = URL(filePath: "/B/Steam/steam.exe")
        XCTAssertEqual(LauncherType.detect(from: url), .steam)
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: LauncherType.detect(from: url), d3dMetalInstalled: true
            ),
            .dxvk
        )
    }
}
