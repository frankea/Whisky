//
//  RockstarD3DSwapResolverTests.swift
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

/// The pure decision a launch makes for the Rockstar Games Launcher's
/// Direct3D: the runtime first, then the user's setting, Wine's sources, and
/// whatever in the bottle would lose DXVK to the swap (#382).
@Suite("Rockstar Direct3D swap resolver")
struct RockstarD3DSwapResolverTests {
    private static let originals = URL(filePath: "/store/originals/d3d11.dll")
    private static let libWine = URL(filePath: "/Libraries/Wine/lib/wine/x86_64-windows/d3d11.dll")
    private static let dxgi = URL(filePath: "/store/originals/dxgi.dll")

    /// Inputs that pass every check, from the store's originals.
    private func passing(_ source: WineD3DSource = .originals(originals)) -> RockstarD3DLayout.Inputs {
        RockstarD3DLayout.Inputs(
            payloadLayout: .degraded(.gptkForwarders), enabled: true, d3d11Source: source,
            dxgiSource: .originals(Self.dxgi)
        )
    }

    @Test("Without the payload the layout is builtin, whatever else the inputs say")
    func builtinWins() {
        var inputs = passing()
        inputs.payloadLayout = .builtin
        inputs.enabled = false
        inputs.bottleUsesNativeD3D11 = true
        inputs.dxvkPlanGames = ["Game"]
        inputs.d3d11Source = .unavailable(.missingFile)

        #expect(RockstarD3DLayout.resolve(inputs) == .builtin)
    }

    @Test("Swapped only when every check passes, from either place Wine's d3d11 can be", arguments: [
        WineD3DSource.originals(originals), .libWine(libWine)
    ])
    func swappedWhenEverythingPasses(_ source: WineD3DSource) throws {
        let url = try #require(source.url)
        #expect(RockstarD3DLayout.resolve(passing(source)) == .swapped(source: url))
    }

    @Test("Each failing check gives its own reason")
    func eachCheckHasItsReason() {
        var disabled = passing()
        disabled.enabled = false
        #expect(RockstarD3DLayout.resolve(disabled) == .degraded(.disabledByUser))

        var noD3D11 = passing()
        noD3D11.d3d11Source = .unavailable(.staleOriginals(found: "4.8.2", expected: "4.8.3"))
        #expect(RockstarD3DLayout.resolve(noD3D11)
            == .degraded(.sourceUnavailable("originals are stamped for 4.8.2, the installed engine is 4.8.3")))

        var noDXGI = passing()
        noDXGI.dxgiSource = .unavailable(.missingFile)
        #expect(RockstarD3DLayout.resolve(noDXGI) == .degraded(.sourceUnavailable("the file is missing")))

        var native = passing()
        native.bottleUsesNativeD3D11 = true
        #expect(RockstarD3DLayout.resolve(native) == .degraded(.bottleUsesNativeD3D11))

        var games = passing()
        games.dxvkPlanGames = ["Zeta", "Alpha"]
        #expect(RockstarD3DLayout.resolve(games) == .degraded(.dxvkPlanGames(["Alpha", "Zeta"])))

        var unserved = passing()
        unserved.unservedConsumers = ["EADesktop.exe", "Benchmark.exe"]
        #expect(RockstarD3DLayout.resolve(unserved)
            == .degraded(.unservedConsumers(["Benchmark.exe", "EADesktop.exe"])))
    }

    @Test("The first check that fails decides, whatever fails after it")
    func firstFailureWins() {
        var inputs = passing()
        inputs.unservedConsumers = ["EADesktop.exe"]
        inputs.dxvkPlanGames = ["Game"]
        inputs.bottleUsesNativeD3D11 = true
        inputs.d3d11Source = .unavailable(.missingFile)
        inputs.enabled = false

        #expect(RockstarD3DLayout.resolve(inputs) == .degraded(.disabledByUser))
        inputs.enabled = true
        #expect(RockstarD3DLayout.resolve(inputs) == .degraded(.sourceUnavailable("the file is missing")))
        inputs.d3d11Source = .originals(Self.originals)
        #expect(RockstarD3DLayout.resolve(inputs) == .degraded(.bottleUsesNativeD3D11))
        inputs.bottleUsesNativeD3D11 = false
        #expect(RockstarD3DLayout.resolve(inputs) == .degraded(.dxvkPlanGames(["Game"])))
        inputs.dxvkPlanGames = []
        #expect(RockstarD3DLayout.resolve(inputs) == .degraded(.unservedConsumers(["EADesktop.exe"])))
    }

    @Test("Launcher.exe draws on Wine's Direct3D on the builtin and swapped layouts only")
    func usesWineDirect3D() {
        #expect(RockstarD3DLayout.builtin.usesWineDirect3D)
        #expect(RockstarD3DLayout.swapped(source: Self.originals).usesWineDirect3D)
        #expect(!RockstarD3DLayout.degraded(.gptkForwarders).usesWineDirect3D)
        #expect(!RockstarD3DLayout.degraded(.swapFailed("x")).usesWineDirect3D)
    }

    @Test("Every summary names its layout and reason, with no Optional wrapping", arguments: [
        RockstarD3DLayout.builtin, .swapped(source: originals), .degraded(.gptkForwarders),
        .degraded(.disabledByUser), .degraded(.sourceUnavailable("the file is missing")),
        .degraded(.bottleUsesNativeD3D11), .degraded(.dxvkPlanGames(["Game"])),
        .degraded(.unservedConsumers(["EADesktop.exe"])), .degraded(.swapFailed("injected"))
    ])
    func summaries(_ layout: RockstarD3DLayout) {
        let summary = layout.summary
        #expect(!summary.contains("Optional("))
        #expect(!summary.contains("\u{2014}"))
        switch layout {
        case .builtin:
            #expect(summary.hasPrefix("builtin ("))
        case .swapped:
            #expect(summary.hasPrefix("swapped ("))
        case let .degraded(reason):
            #expect(summary.hasPrefix("degraded (\(reason.name): "))
        }
    }
}
