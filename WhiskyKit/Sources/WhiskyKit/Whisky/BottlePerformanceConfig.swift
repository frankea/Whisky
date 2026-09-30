//
//  BottlePerformanceConfig.swift
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

public struct BottlePerformanceConfig: Codable, Equatable {
    var shaderCacheEnabled: Bool = true
    var gpuMemoryLimit: Int? // MB, nil means auto
    var forceD3D11: Bool = false // Force D3D11 instead of D3D12 for compatibility
    var disableShaderOptimizations: Bool = false // For debugging FPS issues
    var vcRedistInstalled: Bool = false // Track if VC++ runtime is installed
    var disableAppNap: Bool = false // Prevent macOS from throttling Wine processes

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.shaderCacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .shaderCacheEnabled) ?? true
        self.gpuMemoryLimit = try container.decodeIfPresent(Int.self, forKey: .gpuMemoryLimit)
        self.forceD3D11 = try container.decodeIfPresent(Bool.self, forKey: .forceD3D11) ?? false
        self.disableShaderOptimizations = try container
            .decodeIfPresent(Bool.self, forKey: .disableShaderOptimizations) ?? false
        self.vcRedistInstalled = try container.decodeIfPresent(Bool.self, forKey: .vcRedistInstalled) ?? false
        self.disableAppNap = try container.decodeIfPresent(Bool.self, forKey: .disableAppNap) ?? false
    }
}
