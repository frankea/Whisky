//
//  BottleSettings.swift
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
import SemanticVersion
import os.log

public struct PinnedProgram: Codable, Hashable, Equatable {
    public var name: String
    public var url: URL?
    public var removable: Bool

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
        do {
            let volume = try url.resourceValues(forKeys: [.volumeURLKey]).volume
            self.removable = try !(volume?.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal ?? false)
        } catch {
            self.removable = false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.removable = try container.decodeIfPresent(Bool.self, forKey: .removable) ?? false
    }
}

public struct BottleInfo: Codable, Equatable {
    var name: String = "Bottle"
    var pins: [PinnedProgram] = []
    var blocklist: [URL] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Bottle"
        self.pins = try container.decodeIfPresent([PinnedProgram].self, forKey: .pins) ?? []
        self.blocklist = try container.decodeIfPresent([URL].self, forKey: .blocklist) ?? []
    }
}

public struct BottleSettings: Codable, Equatable {
    static let defaultFileVersion = SemanticVersion(1, 0, 0)

    var fileVersion: SemanticVersion = Self.defaultFileVersion
    private var info: BottleInfo
    private var wineConfig: BottleWineConfig
    private var metalConfig: BottleMetalConfig
    private var dxvkConfig: BottleDXVKConfig
    private var performanceConfig: BottlePerformanceConfig

    public init() {
        self.info = BottleInfo()
        self.wineConfig = BottleWineConfig()
        self.metalConfig = BottleMetalConfig()
        self.dxvkConfig = BottleDXVKConfig()
        self.performanceConfig = BottlePerformanceConfig()
    }

    // swiftlint:disable line_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .fileVersion) ?? Self.defaultFileVersion
        self.info = try container.decodeIfPresent(BottleInfo.self, forKey: .info) ?? BottleInfo()
        self.wineConfig = try container.decodeIfPresent(BottleWineConfig.self, forKey: .wineConfig) ?? BottleWineConfig()
        self.metalConfig = try container.decodeIfPresent(BottleMetalConfig.self, forKey: .metalConfig) ?? BottleMetalConfig()
        self.dxvkConfig = try container.decodeIfPresent(BottleDXVKConfig.self, forKey: .dxvkConfig) ?? BottleDXVKConfig()
        self.performanceConfig = try container.decodeIfPresent(BottlePerformanceConfig.self, forKey: .performanceConfig) ?? BottlePerformanceConfig()
    }
    // swiftlint:enable line_length

    /// The name of this bottle
    public var name: String {
        get { return info.name }
        set { info.name = newValue }
    }

    /// The version of wine used by this bottle
    public var wineVersion: SemanticVersion {
        get { return wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    /// The version of windows used by this bottle
    public var windowsVersion: WinVersion {
        get { return wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    public var avxEnabled: Bool {
        get { return wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    /// The pinned programs on this bottle
    public var pins: [PinnedProgram] {
        get { return info.pins }
        set { info.pins = newValue }
    }

    /// The blocked applicaitons on this bottle
    public var blocklist: [URL] {
        get { return info.blocklist }
        set { info.blocklist = newValue }
    }

    public var enhancedSync: EnhancedSync {
        get { return wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    public var metalHud: Bool {
        get { return metalConfig.metalHud }
        set { metalConfig.metalHud = newValue }
    }

    public var metalTrace: Bool {
        get { return metalConfig.metalTrace }
        set { metalConfig.metalTrace = newValue }
    }

    public var dxrEnabled: Bool {
        get { return metalConfig.dxrEnabled }
        set { metalConfig.dxrEnabled = newValue }
    }

    public var metalValidation: Bool {
        get { return metalConfig.metalValidation }
        set { metalConfig.metalValidation = newValue }
    }

    public var sequoiaCompatMode: Bool {
        get { return metalConfig.sequoiaCompatMode }
        set { metalConfig.sequoiaCompatMode = newValue }
    }

    public var dxvk: Bool {
        get { return dxvkConfig.dxvk }
        set { dxvkConfig.dxvk = newValue }
    }

    public var dxvkAsync: Bool {
        get { return dxvkConfig.dxvkAsync }
        set { dxvkConfig.dxvkAsync = newValue }
    }

    public var dxvkHud: DXVKHUD {
        get {  return dxvkConfig.dxvkHud }
        set { dxvkConfig.dxvkHud = newValue }
    }

    // Performance settings
    public var performancePreset: PerformancePreset {
        get { return performanceConfig.performancePreset }
        set { performanceConfig.performancePreset = newValue }
    }

    public var shaderCacheEnabled: Bool {
        get { return performanceConfig.shaderCacheEnabled }
        set { performanceConfig.shaderCacheEnabled = newValue }
    }

    public var forceD3D11: Bool {
        get { return performanceConfig.forceD3D11 }
        set { performanceConfig.forceD3D11 = newValue }
    }

    public var vcRedistInstalled: Bool {
        get { return performanceConfig.vcRedistInstalled }
        set { performanceConfig.vcRedistInstalled = newValue }
    }

    @discardableResult
    public static func decode(from metadataURL: URL) throws -> BottleSettings {
        guard FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) else {
            let decoder = PropertyListDecoder()
            let settings = try decoder.decode(BottleSettings.self, from: Data(contentsOf: metadataURL))
            try settings.encode(to: metadataURL)
            return settings
        }

        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: metadataURL)
        var settings = try decoder.decode(BottleSettings.self, from: data)

        guard settings.fileVersion == BottleSettings.defaultFileVersion else {
            Logger.wineKit.warning("Invalid file version `\(settings.fileVersion)`")
            settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        if settings.wineConfig.wineVersion != BottleWineConfig().wineVersion {
            Logger.wineKit.warning("Bottle has a different wine version `\(settings.wineConfig.wineVersion)`")
            settings.wineConfig.wineVersion = BottleWineConfig().wineVersion
            try settings.encode(to: metadataURL)
            return settings
        }

        return settings
    }

    func encode(to metadataUrl: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: metadataUrl)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func environmentVariables(wineEnv: inout [String: String]) {
        if dxvk {
            wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=n,b", forKey: "WINEDLLOVERRIDES")
            switch dxvkHud {
            case .full:
                wineEnv.updateValue("full", forKey: "DXVK_HUD")
            case .partial:
                wineEnv.updateValue("devinfo,fps,frametimes", forKey: "DXVK_HUD")
            case .fps:
                wineEnv.updateValue("fps", forKey: "DXVK_HUD")
            case .off:
                break
            }
        }

        if dxvkAsync {
            wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
        }

        switch enhancedSync {
        case .none:
            break
        case .esync:
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        case .msync:
            wineEnv.updateValue("1", forKey: "WINEMSYNC")
            // D3DM detects ESYNC and changes behaviour accordingly
            // so we have to lie to it so that it doesn't break
            // under MSYNC. Values hardcoded in lid3dshared.dylib
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        }

        if metalHud {
            wineEnv.updateValue("1", forKey: "MTL_HUD_ENABLED")
        }

        if metalTrace {
            wineEnv.updateValue("1", forKey: "METAL_CAPTURE_ENABLED")
        }

        if avxEnabled {
            wineEnv.updateValue("1", forKey: "ROSETTA_ADVERTISE_AVX")
        }

        if dxrEnabled {
            wineEnv.updateValue("1", forKey: "D3DM_SUPPORT_DXR")
        }

        // Metal validation - useful for debugging but can impact performance
        if metalValidation {
            wineEnv.updateValue("1", forKey: "MTL_DEBUG_LAYER")
        }

        // macOS Sequoia compatibility mode (#1310, #1372)
        // Applies additional fixes for graphics and launcher issues on macOS 15.x
        if sequoiaCompatMode {
            // Disable problematic Metal shader validation on Sequoia
            // This helps fix graphics corruption issues (#1310)
            if wineEnv["MTL_DEBUG_LAYER"] == nil {
                wineEnv.updateValue("0", forKey: "MTL_DEBUG_LAYER")
            }

            // Stability improvements for D3DMetal on macOS 15.x
            wineEnv.updateValue("0", forKey: "D3DM_VALIDATION")

            // Help with Steam and launcher compatibility (#1307, #1372)
            // Disable Wine's fsync which has issues on Sequoia
            wineEnv.updateValue("0", forKey: "WINEFSYNC")
        }

        // Performance preset handling (#1361 - FPS regression fix)
        applyPerformancePreset(wineEnv: &wineEnv)

        // Shader cache control
        if !shaderCacheEnabled {
            wineEnv.updateValue("1", forKey: "DXVK_SHADER_COMPILE_THREADS")
            wineEnv.updateValue("0", forKey: "__GL_SHADER_DISK_CACHE")
        }

        // Force D3D11 mode - helps with compatibility (#1361)
        if forceD3D11 {
            wineEnv.updateValue("1", forKey: "D3DM_FORCE_D3D11")
            wineEnv.updateValue("0", forKey: "D3DM_FEATURE_LEVEL_12_0")
        }
    }

    private func applyPerformancePreset(wineEnv: inout [String: String]) {
        switch performancePreset {
        case .balanced:
            // Default settings, no changes needed
            break

        case .performance:
            // Performance mode - prioritize FPS over visual quality (#1361 fix)
            // Reduce D3DMetal shader quality for better performance
            wineEnv.updateValue("1", forKey: "D3DM_FAST_SHADER_COMPILE")
            // Disable extra validation that can slow down rendering
            wineEnv.updateValue("0", forKey: "D3DM_VALIDATION")
            wineEnv.updateValue("0", forKey: "MTL_DEBUG_LAYER")
            // Enable DXVK async if not already set
            if wineEnv["DXVK_ASYNC"] == nil {
                wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
            }
            // Use more aggressive shader compilation
            wineEnv.updateValue("0", forKey: "DXVK_SHADER_OPT_LEVEL")
            // Reduce Metal resource tracking overhead
            wineEnv.updateValue("0", forKey: "MTL_ENABLE_METAL_EVENTS")

        case .quality:
            // Quality mode - prioritize visuals over performance
            // Enable shader optimizations
            wineEnv.updateValue("2", forKey: "DXVK_SHADER_OPT_LEVEL")
            // Disable fast shader compile for better quality
            wineEnv.updateValue("0", forKey: "D3DM_FAST_SHADER_COMPILE")

        case .unity:
            // Unity games optimization (#1313, #1312 - il2cpp fix)
            // Unity games often need specific memory and threading settings

            // Fix for il2cpp loading issues
            wineEnv.updateValue("1", forKey: "MONO_THREADS_SUSPEND")
            // Increase file descriptor limit for Unity games
            wineEnv.updateValue("65536", forKey: "WINE_LARGE_ADDRESS_AWARE")

            // Unity games often work better with D3D11
            if wineEnv["D3DM_FORCE_D3D11"] == nil {
                wineEnv.updateValue("1", forKey: "D3DM_FORCE_D3D11")
            }

            // Disable features that can cause issues with Unity's IL2CPP runtime
            wineEnv.updateValue("0", forKey: "WINE_HEAP_REUSE")
            // Help with thread management for Unity's job system
            wineEnv.updateValue("1", forKey: "WINE_DISABLE_NTDLL_THREAD_REGS")

            // Unity games may need more virtual memory
            wineEnv.updateValue("1", forKey: "WINEPRELOADRESERVE")
        }
    }
}
