//
//  Wine+RockstarNativeD3D11.swift
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

/// Who asks for `d3d11` native first, which with the Rockstar swap reaches
/// Wine's own in `system32` unless a `d3d11.dll` sits beside the program (#382).
extension Wine {
    /// Whether the bottle scope, which every process without an entry of its
    /// own reads, asks for `d3d11` native first: a DXVK or DXMT backend, the
    /// Rockstar profile's bottle-wide DXVK preset, or an override of the
    /// user's. With the swap, all of those processes would get Wine's `d3d11`.
    @MainActor
    static func rockstarBottleUsesNativeD3D11(
        bottle: Bottle, recommendedBackend: GraphicsBackend, builtinD3D12IsD3DMetal: Bool
    ) -> Bool {
        let overrides = constructWineEnvironment(
            for: bottle, recommendedBackend: recommendedBackend, builtinD3D12IsD3DMetal: builtinD3D12IsD3DMetal
        )["WINEDLLOVERRIDES"] ?? ""
        return asksNativeFirst("d3d11", in: overrides)
    }

    /// Whether a program on `overrides` loads `d3d11` native first, which
    /// with the swap would reach Wine's in `system32` unless its own folder
    /// holds one: its backend resolves to DXVK, or the overrides composed for
    /// it ask for that some other way, as the entry a launch writes for it
    /// would. That is the legacy DXVK switch on a program with no backend of
    /// its own, or a DLL override of the user's, either of which a check of
    /// the backend alone misses.
    ///
    /// - Parameters:
    ///   - overrides: The program's overrides, or a Steam game's plan.
    ///   - bottle: The bottle.
    ///   - recommendedBackend: What `.recommended` resolves to.
    ///   - dxmtIsServed: Whether a DXMT backend has DXMT's own copies beside
    ///     the program, as a library game on a DXMT plan has (#378), and so
    ///     never reads `system32`'s `d3d11`.
    @MainActor
    static func rockstarProgramUsesNativeD3D11(
        _ overrides: ProgramOverrides?, bottle: Bottle, recommendedBackend: GraphicsBackend, dxmtIsServed: Bool
    ) -> Bool {
        let choice = overrides?.graphicsBackend ?? bottle.settings.graphicsBackend
        let backend = choice == .recommended ? recommendedBackend : choice
        if backend == .dxvk {
            return true
        }
        if backend == .dxmt, dxmtIsServed {
            return false
        }
        // The consumer scan only runs with the GPTK payload deployed.
        let composed = constructWineEnvironment(
            for: bottle, programOverrides: overrides, recommendedBackend: recommendedBackend,
            builtinD3D12IsD3DMetal: true
        )["WINEDLLOVERRIDES"] ?? ""
        return asksNativeFirst("d3d11", in: composed)
    }

    /// Whether `overrides`, in `WINEDLLOVERRIDES` syntax, load `dll` native
    /// first. A clause may name several DLLs (`d3d11,dxgi=n,b`); the last
    /// clause naming `dll` wins, as in Wine.
    static func asksNativeFirst(_ dll: String, in overrides: String) -> Bool {
        var nativeFirst = false
        for clause in overrides.split(separator: ";") {
            let parts = clause.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let names = parts.first,
                  names.split(separator: ",").contains(where: {
                      $0.trimmingCharacters(in: .whitespaces).lowercased() == dll
                  })
            else { continue }
            let order = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces).lowercased() : ""
            nativeFirst = order.hasPrefix("n")
        }
        return nativeFirst
    }
}
