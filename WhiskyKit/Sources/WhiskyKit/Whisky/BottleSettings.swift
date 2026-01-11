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

/// Represents a pinned program entry in a bottle's quick-access list.
///
/// Pinned programs appear in a prominent location in the UI for fast access.
/// The pin tracks whether the program is on a removable volume so it can
/// handle disconnected drives gracefully.
public struct PinnedProgram: Codable, Hashable, Equatable {
    /// The display name for the pinned program.
    public var name: String
    
    /// The URL to the program's executable file.
    public var url: URL?
    
    /// Whether the program is stored on a removable volume.
    ///
    /// When `true`, the pin remains valid even if the volume is disconnected.
    public var removable: Bool

    /// Creates a new pinned program entry.
    ///
    /// - Parameters:
    ///   - name: The display name for the pin.
    ///   - url: The URL to the program's executable.
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

/// Basic information about a bottle including its name and pinned programs.
///
/// This struct contains the user-visible metadata for a bottle that isn't
/// related to Wine configuration.
public struct BottleInfo: Codable, Equatable {
    /// The display name of the bottle.
    var name: String = "Bottle"
    
    /// The list of pinned programs for quick access.
    var pins: [PinnedProgram] = []
    
    /// URLs of programs that should be hidden from the program list.
    var blocklist: [URL] = []

    /// Creates a new BottleInfo with default values.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Bottle"
        self.pins = try container.decodeIfPresent([PinnedProgram].self, forKey: .pins) ?? []
        self.blocklist = try container.decodeIfPresent([URL].self, forKey: .blocklist) ?? []
    }
}

/// The complete configuration settings for a Wine bottle.
///
/// `BottleSettings` is the main configuration type for a bottle, containing all
/// settings related to Wine, Metal graphics, DXVK, and performance. It's automatically
/// serialized to a plist file in the bottle directory.
///
/// ## Overview
///
/// Settings are organized into logical groups:
/// - **Info**: Name, pins, and blocklist
/// - **Wine Config**: Windows version, AVX, enhanced sync
/// - **Metal Config**: Metal HUD, DXR, validation
/// - **DXVK Config**: DXVK enable, async, HUD
/// - **Performance Config**: Presets, shader cache, D3D11 mode
///
/// ## Example
///
/// ```swift
/// var settings = BottleSettings()
/// settings.name = "Gaming"
/// settings.windowsVersion = .win10
/// settings.dxvk = true
/// settings.performancePreset = .performance
/// ```
///
/// ## Topics
///
/// ### Basic Information
/// - ``name``
/// - ``pins``
/// - ``blocklist``
///
/// ### Wine Configuration
/// - ``windowsVersion``
/// - ``wineVersion``
/// - ``avxEnabled``
/// - ``enhancedSync``
///
/// ### Graphics Settings
/// - ``metalHud``
/// - ``metalTrace``
/// - ``metalValidation``
/// - ``dxrEnabled``
/// - ``sequoiaCompatMode``
///
/// ### DXVK Settings
/// - ``dxvk``
/// - ``dxvkAsync``
/// - ``dxvkHud``
///
/// ### Performance
/// - ``performancePreset``
/// - ``shaderCacheEnabled``
/// - ``forceD3D11``
/// - ``vcRedistInstalled``
public struct BottleSettings: Codable, Equatable {
    /// The current file format version for settings serialization.
    static let defaultFileVersion = SemanticVersion(1, 0, 0)

    /// The version of the settings file format.
    var fileVersion: SemanticVersion = Self.defaultFileVersion
    
    /// Basic bottle information (name, pins).
    private var info: BottleInfo
    
    /// Wine-specific configuration.
    private var wineConfig: BottleWineConfig
    
    /// Metal graphics settings.
    private var metalConfig: BottleMetalConfig
    
    /// DXVK translation layer settings.
    private var dxvkConfig: BottleDXVKConfig
    
    /// Performance optimization settings.
    private var performanceConfig: BottlePerformanceConfig

    /// Creates a new BottleSettings instance with default values.
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

    /// The display name of this bottle.
    public var name: String {
        get { return info.name }
        set { info.name = newValue }
    }

    /// The Wine version used when this bottle was created.
    ///
    /// This is automatically updated when Wine is upgraded.
    public var wineVersion: SemanticVersion {
        get { return wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    /// The Windows version that Wine emulates for this bottle.
    ///
    /// Different Windows versions may provide better compatibility
    /// for different applications. Windows 10 is recommended for most games.
    public var windowsVersion: WinVersion {
        get { return wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    /// Whether AVX instruction set support is advertised to programs.
    ///
    /// Enable this via Rosetta 2 for programs that require AVX instructions.
    /// Only applicable on Apple Silicon Macs.
    public var avxEnabled: Bool {
        get { return wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    /// The list of pinned programs for quick access.
    public var pins: [PinnedProgram] {
        get { return info.pins }
        set { info.pins = newValue }
    }

    /// URLs of programs that should be hidden from the program list.
    ///
    /// Use this to hide unwanted executables like installers or utilities.
    public var blocklist: [URL] {
        get { return info.blocklist }
        set { info.blocklist = newValue }
    }

    /// The synchronization mode for Wine.
    ///
    /// Enhanced sync modes (ESync/MSync) can improve performance
    /// by using more efficient synchronization primitives.
    public var enhancedSync: EnhancedSync {
        get { return wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    /// Whether to display the Metal performance HUD overlay.
    ///
    /// Shows frame rate and GPU statistics during gameplay.
    public var metalHud: Bool {
        get { return metalConfig.metalHud }
        set { metalConfig.metalHud = newValue }
    }

    /// Whether to enable Metal GPU trace capture.
    ///
    /// Useful for debugging graphics issues with Xcode's GPU debugger.
    public var metalTrace: Bool {
        get { return metalConfig.metalTrace }
        set { metalConfig.metalTrace = newValue }
    }

    /// Whether DirectX Raytracing (DXR) support is enabled.
    ///
    /// Enable this for games that support ray tracing features.
    public var dxrEnabled: Bool {
        get { return metalConfig.dxrEnabled }
        set { metalConfig.dxrEnabled = newValue }
    }

    /// Whether Metal validation layer is enabled.
    ///
    /// Useful for debugging but impacts performance. Keep disabled
    /// for normal gameplay.
    public var metalValidation: Bool {
        get { return metalConfig.metalValidation }
        set { metalConfig.metalValidation = newValue }
    }

    /// Whether macOS Sequoia (15.x) compatibility mode is enabled.
    ///
    /// Applies additional fixes for graphics and launcher issues
    /// specific to macOS 15.x. Enable if experiencing problems.
    public var sequoiaCompatMode: Bool {
        get { return metalConfig.sequoiaCompatMode }
        set { metalConfig.sequoiaCompatMode = newValue }
    }

    /// Whether DXVK is enabled for DirectX-to-Vulkan translation.
    ///
    /// DXVK often provides better performance than Wine's built-in
    /// DirectX implementation, especially for DirectX 9/10/11 games.
    public var dxvk: Bool {
        get { return dxvkConfig.dxvk }
        set { dxvkConfig.dxvk = newValue }
    }

    /// Whether DXVK async shader compilation is enabled.
    ///
    /// Reduces stuttering during gameplay by compiling shaders
    /// asynchronously, at the cost of potential visual glitches.
    public var dxvkAsync: Bool {
        get { return dxvkConfig.dxvkAsync }
        set { dxvkConfig.dxvkAsync = newValue }
    }

    /// The DXVK HUD display mode.
    ///
    /// Controls what information is shown in the DXVK overlay.
    public var dxvkHud: DXVKHUD {
        get {  return dxvkConfig.dxvkHud }
        set { dxvkConfig.dxvkHud = newValue }
    }

    // MARK: - Performance settings
    
    /// The performance optimization preset.
    ///
    /// Presets configure multiple settings at once for different
    /// use cases like gaming, quality, or Unity games.
    public var performancePreset: PerformancePreset {
        get { return performanceConfig.performancePreset }
        set { performanceConfig.performancePreset = newValue }
    }

    /// Whether shader caching is enabled.
    ///
    /// Shader caching reduces stuttering after the first run
    /// by storing compiled shaders on disk.
    public var shaderCacheEnabled: Bool {
        get { return performanceConfig.shaderCacheEnabled }
        set { performanceConfig.shaderCacheEnabled = newValue }
    }

    /// Whether to force DirectX 11 mode instead of DirectX 12.
    ///
    /// Some games have better compatibility with D3D11. Enable
    /// this if experiencing issues with graphics or crashes.
    public var forceD3D11: Bool {
        get { return performanceConfig.forceD3D11 }
        set { performanceConfig.forceD3D11 = newValue }
    }

    /// Whether Visual C++ Redistributable is installed in this bottle.
    ///
    /// Track this to avoid redundant installation prompts.
    public var vcRedistInstalled: Bool {
        get { return performanceConfig.vcRedistInstalled }
        set { performanceConfig.vcRedistInstalled = newValue }
    }

    /// Loads bottle settings from a metadata plist file.
    ///
    /// This method handles version migration and validation. If the settings
    /// file doesn't exist or has an incompatible version, default settings
    /// are created.
    ///
    /// - Parameter metadataURL: The URL to the Metadata.plist file.
    /// - Returns: The loaded or newly created settings.
    /// - Throws: An error if the file cannot be read or decoded.
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

    /// Saves the settings to a plist file.
    ///
    /// - Parameter metadataUrl: The URL where settings should be saved.
    /// - Throws: An error if the settings cannot be encoded or written.
    func encode(to metadataUrl: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: metadataUrl)
    }

    /// Populates a Wine environment dictionary based on these settings.
    ///
    /// This method examines all configuration options and adds the appropriate
    /// environment variables to enable DXVK, Metal features, sync modes,
    /// performance optimizations, and other settings.
    ///
    /// - Parameter wineEnv: The environment dictionary to populate.
    ///   Existing values may be modified or removed based on settings.
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
            // On macOS 15.4+, WINEESYNC is required for stability
            if MacOSVersion.current < .sequoia15_4 {
                wineEnv.removeValue(forKey: "WINEESYNC")
                wineEnv.removeValue(forKey: "WINEMSYNC")
            } else {
                // Ensure a stable default on newer macOS versions:
                // enable ESYNC and clear any conflicting MSYNC setting.
                wineEnv.updateValue("1", forKey: "WINEESYNC")
                wineEnv.removeValue(forKey: "WINEMSYNC")
            }
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
        if sequoiaCompatMode && MacOSVersion.current.major >= 15 {
            // Disable problematic Metal shader validation on Sequoia
            // This helps fix graphics corruption issues (#1310)
            wineEnv.updateValue("0", forKey: "MTL_DEBUG_LAYER")

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
