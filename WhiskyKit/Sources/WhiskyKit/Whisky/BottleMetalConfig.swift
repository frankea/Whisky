//
//  BottleMetalConfig.swift
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

public struct BottleMetalConfig: Codable, Equatable {
    var metalHud: Bool = false
    var metalTrace: Bool = false
    var dxrEnabled: Bool = false
    var metalValidation: Bool = false
    var forceGPUFamily: String?
    /// Converts DLSS calls to MetalFX where possible (GPTK 4, `D3DM_ENABLE_METALFX`).
    ///
    /// Requires Apple's NVIDIA bridge DLLs in the bottle; without them a game finds no
    /// `nvapi64` and simply renders without upscaling. macOS 26 Tahoe or later.
    var metalFXEnabled: Bool = false
    /// Uses D3DMetal's Metal 4 backend for D3D12 translation (GPTK 4, `D3DM_MTL4`).
    ///
    /// Apple enables this by default on macOS 27+. Turning it off falls back to the Metal 3
    /// backend, which is worth trying when a D3D12 title regresses on a new OS.
    var metal4Backend: Bool = true
    /// Caps the frame rate (GPTK 4, `D3DM_MAX_FPS`). Zero leaves it uncapped.
    ///
    /// Useful against the coil whine and thermal throttling that menu screens cause when they
    /// render at several hundred frames per second.
    var maxFPS: Int = 0
    /// Sequoia-era workarounds, on by default only on the OS they were written for.
    ///
    /// Previously defaulted on everywhere, which meant a machine on Tahoe or Golden Gate had
    /// fsync and Metal validation disabled for 15.x bugs it never had. Still available as a
    /// manual toggle on any OS for anyone who needs it back.
    var sequoiaCompatMode: Bool = MacOSVersion.current.isSequoiaOrEarlier

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.metalHud = try container.decodeIfPresent(Bool.self, forKey: .metalHud) ?? false
        self.metalTrace = try container.decodeIfPresent(Bool.self, forKey: .metalTrace) ?? false
        self.dxrEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxrEnabled) ?? false
        self.metalValidation = try container.decodeIfPresent(Bool.self, forKey: .metalValidation) ?? false
        self.forceGPUFamily = try container.decodeIfPresent(String.self, forKey: .forceGPUFamily)
        self.metalFXEnabled = try container.decodeIfPresent(Bool.self, forKey: .metalFXEnabled) ?? false
        self.metal4Backend = try container.decodeIfPresent(Bool.self, forKey: .metal4Backend) ?? true
        self.maxFPS = try container.decodeIfPresent(Int.self, forKey: .maxFPS) ?? 0
        self.sequoiaCompatMode = try container.decodeIfPresent(Bool.self, forKey: .sequoiaCompatMode)
            ?? MacOSVersion.current.isSequoiaOrEarlier
    }
}
