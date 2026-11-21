//
//  D3DSharedLibraryPathTests.swift
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
@testable import WhiskyKit
import XCTest

/// Wine's ntdll loads Apple's `libd3dshared.dylib` only from the path in
/// `CX_APPLEGPTK_LIBD3DSHARED_PATH`. Without it, D3DMetal games can hang at
/// start with `Exception c0000005 in system thread`.
final class D3DSharedLibraryPathTests: LauncherFixesTestCase {
    let variable = "CX_APPLEGPTK_LIBD3DSHARED_PATH"

    @MainActor
    func testLaunchWithTheGPTKPayloadNamesTheSharedLibrary() {
        let env = Wine.constructWineEnvironment(
            for: makeBottle(), recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
        )

        let expected = GPTKImporter.sharedLibrary(inLibraryFolder: WhiskyWineInstaller.libraryFolder)
        XCTAssertEqual(env[variable], expected.path(percentEncoded: false))
        XCTAssertTrue(expected.path(percentEncoded: false).hasSuffix("/Wine/lib/external/libd3dshared.dylib"))
    }

    @MainActor
    func testLaunchOnAnotherBackendStillNamesTheSharedLibrary() {
        // A launcher on DXVK starts games that run on D3DMetal, and a game
        // inherits the environment of the launcher that started it.
        let bottle = makeBottle()
        bottle.settings.graphicsBackend = .dxvk

        let env = Wine.constructWineEnvironment(
            for: bottle, recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
        )

        XCTAssertNotNil(env[variable])
    }

    @MainActor
    func testLaunchWithoutTheGPTKPayloadLeavesTheVariableUnset() {
        let env = Wine.constructWineEnvironment(
            for: makeBottle(), recommendedBackend: .dxmt, builtinD3D12IsD3DMetal: false
        )

        XCTAssertNil(env[variable])
    }

    @MainActor
    func testTheProgramCanStillSetItsOwnPath() {
        let env = Wine.constructWineEnvironment(
            for: makeBottle(), environment: [variable: "/custom/libd3dshared.dylib"],
            recommendedBackend: .d3dMetal, builtinD3D12IsD3DMetal: true
        )

        XCTAssertEqual(env[variable], "/custom/libd3dshared.dylib")
    }
}
