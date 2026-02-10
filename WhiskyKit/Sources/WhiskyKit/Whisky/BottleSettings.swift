// swiftlint:disable file_length
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
import os.log
import SemanticVersion

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

// swiftlint:disable type_body_length
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
    /// Game launcher compatibility settings.
    private var launcherConfig: BottleLauncherConfig
    /// Controller and input device settings.
    private var inputConfig: BottleInputConfig
    /// Cleanup and clipboard behavior settings.
    private var cleanupConfig: BottleCleanupConfig
    /// Graphics backend selection.
    private var graphicsConfig: BottleGraphicsConfig
    /// Audio driver, latency, and device settings.
    private var audioConfig: BottleAudioConfig
    /// User-defined DLL overrides at the bottle level.
    private var customDLLOverrides: [DLLOverrideEntry] = []

    /// Creates a new BottleSettings instance with default values.
    public init() {
        self.info = BottleInfo()
        self.wineConfig = BottleWineConfig()
        self.metalConfig = BottleMetalConfig()
        self.dxvkConfig = BottleDXVKConfig()
        self.performanceConfig = BottlePerformanceConfig()
        self.launcherConfig = BottleLauncherConfig()
        self.inputConfig = BottleInputConfig()
        self.cleanupConfig = BottleCleanupConfig()
        self.graphicsConfig = BottleGraphicsConfig()
        self.audioConfig = BottleAudioConfig()
        self.customDLLOverrides = []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .fileVersion) ?? Self
            .defaultFileVersion
        self.info = try container.decodeIfPresent(BottleInfo.self, forKey: .info) ?? BottleInfo()
        self.wineConfig = try container
            .decodeIfPresent(BottleWineConfig.self, forKey: .wineConfig) ?? BottleWineConfig()
        self.metalConfig = try container
            .decodeIfPresent(BottleMetalConfig.self, forKey: .metalConfig) ?? BottleMetalConfig()
        self.dxvkConfig = try container
            .decodeIfPresent(BottleDXVKConfig.self, forKey: .dxvkConfig) ?? BottleDXVKConfig()
        self.performanceConfig = try container.decodeIfPresent(
            BottlePerformanceConfig.self,
            forKey: .performanceConfig
        ) ?? BottlePerformanceConfig()
        self.launcherConfig = try container.decodeIfPresent(
            BottleLauncherConfig.self,
            forKey: .launcherConfig
        ) ?? BottleLauncherConfig()
        self.inputConfig = try container.decodeIfPresent(
            BottleInputConfig.self,
            forKey: .inputConfig
        ) ?? BottleInputConfig()
        self.cleanupConfig = try container.decodeIfPresent(
            BottleCleanupConfig.self,
            forKey: .cleanupConfig
        ) ?? BottleCleanupConfig()
        let hasGraphicsConfig = container.contains(.graphicsConfig)
        self.graphicsConfig = try container.decodeIfPresent(
            BottleGraphicsConfig.self,
            forKey: .graphicsConfig
        ) ?? BottleGraphicsConfig()
        // Migration: preserve DXVK choice from old bottles that lack graphicsConfig
        if !hasGraphicsConfig, self.dxvkConfig.dxvk {
            self.graphicsConfig.backend = .dxvk
        }
        self.audioConfig = try container.decodeIfPresent(
            BottleAudioConfig.self,
            forKey: .audioConfig
        ) ?? BottleAudioConfig()
        self.customDLLOverrides = try container.decodeIfPresent(
            [DLLOverrideEntry].self,
            forKey: .customDLLOverrides
        ) ?? []
    }

    /// The display name of this bottle.
    public var name: String {
        get { info.name }
        set { info.name = newValue }
    }

    /// The Wine version used when this bottle was created.
    ///
    /// This is automatically updated when Wine is upgraded.
    public var wineVersion: SemanticVersion {
        get { wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    /// The Windows version that Wine emulates for this bottle.
    ///
    /// Different Windows versions may provide better compatibility
    /// for different applications. Windows 10 is recommended for most games.
    public var windowsVersion: WinVersion {
        get { wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    /// Whether AVX instruction set support is advertised to programs.
    ///
    /// Enable this via Rosetta 2 for programs that require AVX instructions.
    /// Only applicable on Apple Silicon Macs.
    public var avxEnabled: Bool {
        get { wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    /// The list of pinned programs for quick access.
    public var pins: [PinnedProgram] {
        get { info.pins }
        set { info.pins = newValue }
    }

    /// URLs of programs that should be hidden from the program list.
    ///
    /// Use this to hide unwanted executables like installers or utilities.
    public var blocklist: [URL] {
        get { info.blocklist }
        set { info.blocklist = newValue }
    }

    /// The synchronization mode for Wine.
    ///
    /// Enhanced sync modes (ESync/MSync) can improve performance for some applications
    /// by using more efficient synchronization primitives.
    public var enhancedSync: EnhancedSync {
        get { wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    /// Whether to display the Metal performance HUD overlay.
    ///
    /// Shows frame rate and GPU statistics during gameplay.
    public var metalHud: Bool {
        get { metalConfig.metalHud }
        set { metalConfig.metalHud = newValue }
    }

    /// Whether to enable Metal GPU trace capture.
    ///
    /// Useful for debugging graphics issues with Xcode's GPU debugger.
    public var metalTrace: Bool {
        get { metalConfig.metalTrace }
        set { metalConfig.metalTrace = newValue }
    }

    /// Whether DirectX Raytracing (DXR) support is enabled.
    ///
    /// Enable this for games that support ray tracing features.
    public var dxrEnabled: Bool {
        get { metalConfig.dxrEnabled }
        set { metalConfig.dxrEnabled = newValue }
    }

    /// Whether Metal validation layer is enabled.
    ///
    /// Useful for debugging but impacts performance. Keep disabled
    /// for normal gameplay.
    public var metalValidation: Bool {
        get { metalConfig.metalValidation }
        set { metalConfig.metalValidation = newValue }
    }

    /// Whether macOS Sequoia (15.x) compatibility mode is enabled.
    ///
    /// Applies additional fixes for graphics and launcher issues
    /// specific to macOS 15.x. Enable if experiencing problems.
    public var sequoiaCompatMode: Bool {
        get { metalConfig.sequoiaCompatMode }
        set { metalConfig.sequoiaCompatMode = newValue }
    }

    /// The graphics backend for this bottle.
    ///
    /// Controls which translation layer is used for Direct3D rendering.
    /// `.recommended` resolves to a concrete backend at launch time based on GPU/OS heuristics.
    public var graphicsBackend: GraphicsBackend {
        get { graphicsConfig.backend }
        set { graphicsConfig.backend = newValue }
    }

    /// Whether DXVK is the active graphics backend.
    ///
    /// This property now derives from ``graphicsBackend``. Setting it to `true`
    /// switches the backend to `.dxvk`; setting to `false` switches to `.recommended`.
    public var dxvk: Bool {
        get { graphicsConfig.backend == .dxvk }
        set { graphicsConfig.backend = newValue ? .dxvk : .recommended }
    }

    /// Whether DXVK async shader compilation is enabled.
    ///
    /// Reduces stuttering during gameplay by compiling shaders
    /// asynchronously, at the cost of potential visual glitches.
    public var dxvkAsync: Bool {
        get { dxvkConfig.dxvkAsync }
        set { dxvkConfig.dxvkAsync = newValue }
    }

    /// The DXVK HUD display mode.
    ///
    /// Controls what information is shown in the DXVK overlay.
    public var dxvkHud: DXVKHUD {
        get { dxvkConfig.dxvkHud }
        set { dxvkConfig.dxvkHud = newValue }
    }

    // MARK: - Audio settings

    /// The audio driver mode for this bottle.
    ///
    /// Controls which audio driver Wine uses. `.auto` lets Wine choose
    /// the best driver (CoreAudio on macOS). Audio driver configuration
    /// is applied via the Wine registry, not environment variables.
    public var audioDriver: AudioDriverMode {
        get { audioConfig.audioDriver }
        set { audioConfig.audioDriver = newValue }
    }

    /// The audio latency preset for this bottle.
    ///
    /// Controls the DirectSound `HelBuflen` buffer size. Larger buffers
    /// improve stability with Bluetooth and USB audio at the cost of
    /// increased latency. Applied via the Wine registry.
    public var audioLatencyPreset: AudioLatencyPreset {
        get { audioConfig.latencyPreset }
        set { audioConfig.latencyPreset = newValue }
    }

    /// The output device routing mode for this bottle.
    ///
    /// Controls whether Wine follows the macOS default output device
    /// or is pinned to a specific device by name.
    public var outputDeviceMode: OutputDeviceMode {
        get { audioConfig.outputDeviceMode }
        set { audioConfig.outputDeviceMode = newValue }
    }

    /// The name of the pinned audio output device, if any.
    ///
    /// Only meaningful when ``outputDeviceMode`` is `.pinned`.
    /// Set to `nil` to clear the pin and follow the system default.
    public var pinnedDeviceName: String? {
        get { audioConfig.pinnedDeviceName }
        set { audioConfig.pinnedDeviceName = newValue }
    }

    // MARK: - Performance settings

    /// The performance optimization preset.
    ///
    /// Presets configure multiple settings at once for different
    /// use cases like gaming, quality, or Unity games.
    public var performancePreset: PerformancePreset {
        get { performanceConfig.performancePreset }
        set { performanceConfig.performancePreset = newValue }
    }

    /// Whether shader caching is enabled.
    ///
    /// Shader caching reduces stuttering after the first run
    /// by storing compiled shaders on disk.
    public var shaderCacheEnabled: Bool {
        get { performanceConfig.shaderCacheEnabled }
        set { performanceConfig.shaderCacheEnabled = newValue }
    }

    /// Whether to force DirectX 11 mode instead of DirectX 12.
    ///
    /// Some games have better compatibility with D3D11. Enable
    /// this if experiencing issues with graphics or crashes.
    public var forceD3D11: Bool {
        get { performanceConfig.forceD3D11 }
        set { performanceConfig.forceD3D11 = newValue }
    }

    /// Whether Visual C++ Redistributable is installed in this bottle.
    ///
    /// Track this to avoid redundant installation prompts.
    public var vcRedistInstalled: Bool {
        get { performanceConfig.vcRedistInstalled }
        set { performanceConfig.vcRedistInstalled = newValue }
    }

    /// Whether App Nap should be disabled for Wine processes.
    ///
    /// When enabled, prevents macOS from throttling Wine processes
    /// when the application is in the background, improving game performance.
    public var disableAppNap: Bool {
        get { performanceConfig.disableAppNap }
        set { performanceConfig.disableAppNap = newValue }
    }

    // MARK: - Launcher compatibility settings

    /// Whether launcher compatibility mode is enabled.
    ///
    /// When enabled, applies launcher-specific optimizations for Steam,
    /// Rockstar, EA App, Epic Games, and other platforms (frankea/Whisky#41).
    public var launcherCompatibilityMode: Bool {
        get { launcherConfig.compatibilityMode }
        set { launcherConfig.compatibilityMode = newValue }
    }

    /// The launcher detection mode (auto or manual).
    ///
    /// - **Auto**: Detects launcher from executable path automatically
    /// - **Manual**: Uses explicitly selected launcher type
    public var launcherMode: LauncherMode {
        get { launcherConfig.launcherMode }
        set { launcherConfig.launcherMode = newValue }
    }

    /// Manually selected or auto-detected launcher type.
    ///
    /// Used when `launcherCompatibilityMode` is enabled to apply
    /// launcher-specific environment variables and settings.
    public var detectedLauncher: LauncherType? {
        get { launcherConfig.detectedLauncher }
        set { launcherConfig.detectedLauncher = newValue }
    }

    /// Locale override for launcher compatibility.
    ///
    /// Steam and other Chromium-based launchers require `en_US.UTF-8`
    /// to avoid steamwebhelper crashes (whisky-app/whisky#946, #1224, #1241).
    public var launcherLocale: Locales {
        get { launcherConfig.launcherLocale }
        set { launcherConfig.launcherLocale = newValue }
    }

    /// Whether to enable GPU spoofing for launcher compatibility.
    ///
    /// Reports high-end GPU capabilities to pass launcher checks.
    /// Fixes EA App black screen and "GPU not supported" errors.
    public var gpuSpoofing: Bool {
        get { launcherConfig.gpuSpoofing }
        set { launcherConfig.gpuSpoofing = newValue }
    }

    /// GPU vendor to spoof when GPU spoofing is enabled.
    ///
    /// NVIDIA (default) provides best compatibility across launchers.
    public var gpuVendor: GPUVendor {
        get { launcherConfig.gpuVendor }
        set { launcherConfig.gpuVendor = newValue }
    }

    /// Network timeout in milliseconds for launcher downloads.
    ///
    /// Addresses Steam download stalls and connection timeouts.
    public var networkTimeout: Int {
        get { launcherConfig.networkTimeout }
        set { launcherConfig.networkTimeout = newValue }
    }

    /// Whether to automatically enable DXVK when launcher requires it.
    ///
    /// Rockstar Games Launcher requires DXVK to render logo screen.
    public var autoEnableDXVK: Bool {
        get { launcherConfig.autoEnableDXVK }
        set { launcherConfig.autoEnableDXVK = newValue }
    }

    // MARK: - Controller and input settings

    /// Whether controller compatibility mode is enabled.
    ///
    /// When enabled, applies workarounds for common controller detection
    /// and mapping issues on macOS (frankea/Whisky#42).
    public var controllerCompatibilityMode: Bool {
        get { inputConfig.controllerCompatibilityMode }
        set { inputConfig.controllerCompatibilityMode = newValue }
    }

    /// Whether to disable HIDAPI for joystick input.
    ///
    /// Forces SDL to use alternative backends which may improve
    /// detection for some controllers.
    public var disableHIDAPI: Bool {
        get { inputConfig.disableHIDAPI }
        set { inputConfig.disableHIDAPI = newValue }
    }

    /// Whether to allow joystick events when app is in background.
    ///
    /// Enables controller input even when Wine window doesn't have focus.
    public var allowBackgroundEvents: Bool {
        get { inputConfig.allowBackgroundEvents }
        set { inputConfig.allowBackgroundEvents = newValue }
    }

    /// Whether to disable SDL to XInput mapping conversion.
    ///
    /// May help PlayStation and Switch controllers show correct button mappings.
    public var disableControllerMapping: Bool {
        get { inputConfig.disableControllerMapping }
        set { inputConfig.disableControllerMapping = newValue }
    }

    // MARK: - Custom DLL overrides

    /// User-defined DLL overrides for this bottle.
    ///
    /// These overrides are composed with managed overrides (from DXVK toggle
    /// and launcher presets) by ``DLLOverrideResolver``. Bottle custom overrides
    /// take precedence over managed overrides per-DLL.
    public var dllOverrides: [DLLOverrideEntry] {
        get { customDLLOverrides }
        set { customDLLOverrides = newValue }
    }

    // MARK: - Cleanup and clipboard settings

    /// The clipboard handling policy for this bottle.
    ///
    /// Controls how clipboard content is checked before launching Wine programs.
    /// See ``ClipboardPolicy`` for available options.
    public var clipboardPolicy: ClipboardPolicy {
        get { cleanupConfig.clipboardPolicy }
        set { cleanupConfig.clipboardPolicy = newValue }
    }

    /// The size threshold in bytes for considering clipboard content "large".
    ///
    /// Content above this threshold triggers the configured clipboard policy.
    /// Defaults to ``ClipboardManager/largeContentThreshold`` (10 KB).
    public var clipboardThreshold: Int {
        get { cleanupConfig.clipboardThreshold }
        set { cleanupConfig.clipboardThreshold = newValue }
    }

    /// The kill-on-quit policy for Wine processes in this bottle.
    ///
    /// Overrides the global `killOnTerminate` setting on a per-bottle basis.
    /// See ``KillOnQuitPolicy`` for available options.
    public var killOnQuit: KillOnQuitPolicy {
        get { cleanupConfig.killOnQuit }
        set { cleanupConfig.killOnQuit = newValue }
    }

    /// The policy for handling running processes when navigating away from this bottle.
    ///
    /// Controls whether a confirmation dialog is shown when the user switches
    /// to a different bottle while Wine processes are still running.
    /// See ``CloseWithProcessesPolicy`` for available options.
    public var closeWithProcessesPolicy: CloseWithProcessesPolicy {
        get { cleanupConfig.closeWithProcessesPolicy }
        set { cleanupConfig.closeWithProcessesPolicy = newValue }
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
            // File doesn't exist - create default settings and save them
            let settings = BottleSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        // File exists - read and decode it
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

    // MARK: - EnvironmentBuilder Layer Populators

    // swiftlint:disable cyclomatic_complexity function_body_length

    /// Populates the ``EnvironmentLayer/bottleManaged`` layer with settings-derived env vars.
    ///
    /// This method replaces the direct dict mutation in the deprecated ``environmentVariables(wineEnv:)``.
    /// DLL override entries are returned separately for composition by ``DLLOverrideResolver``.
    ///
    /// - Parameter builder: The environment builder to populate.
    /// - Returns: Managed DLL override entries with their sources for the DLLOverrideResolver.
    public func populateBottleManagedLayer(
        builder: inout EnvironmentBuilder
    ) -> [(entry: DLLOverrideEntry, source: DLLOverrideSource)] {
        var managedDLLOverrides: [(entry: DLLOverrideEntry, source: DLLOverrideSource)] = []

        // Resolve the graphics backend (`.recommended` -> concrete backend)
        let resolvedBackend = if graphicsBackend == .recommended {
            GraphicsBackendResolver.resolve()
        } else {
            graphicsBackend
        }

        // Backend-conditional env vars and DLL overrides
        switch resolvedBackend {
        case .d3dMetal, .recommended:
            // D3DMetal is Wine's default on macOS -- no special env vars needed
            break

        case .dxvk:
            // DXVK: DLL overrides + env vars
            for entry in DLLOverrideResolver.dxvkPreset {
                managedDLLOverrides.append((entry: entry, source: .dxvk))
            }
            switch dxvkHud {
            case .full:
                builder.set("DXVK_HUD", "full", layer: .bottleManaged)
            case .partial:
                builder.set("DXVK_HUD", "devinfo,fps,frametimes", layer: .bottleManaged)
            case .fps:
                builder.set("DXVK_HUD", "fps", layer: .bottleManaged)
            case .off:
                break
            }
            if dxvkAsync {
                builder.set("DXVK_ASYNC", "1", layer: .bottleManaged)
            }

        case .wined3d:
            // Disable D3DMetal, forcing Wine's OpenGL-based wined3d path
            builder.set("WINED3DMETAL", "0", layer: .bottleManaged)
        }

        // Enhanced sync mode
        switch enhancedSync {
        case .none:
            // On macOS 15.4+, WINEESYNC is required for stability
            if MacOSVersion.current < .sequoia15_4 {
                builder.remove("WINEESYNC", layer: .bottleManaged)
                builder.remove("WINEMSYNC", layer: .bottleManaged)
            } else {
                // Ensure a stable default on newer macOS versions:
                // enable ESYNC and clear any conflicting MSYNC setting.
                builder.set("WINEESYNC", "1", layer: .bottleManaged)
                builder.remove("WINEMSYNC", layer: .bottleManaged)
            }
        case .esync:
            builder.set("WINEESYNC", "1", layer: .bottleManaged)
        case .msync:
            builder.set("WINEMSYNC", "1", layer: .bottleManaged)
            // D3DM detects ESYNC and changes behaviour accordingly
            // so we have to lie to it so that it doesn't break
            // under MSYNC. Values hardcoded in lid3dshared.dylib
            builder.set("WINEESYNC", "1", layer: .bottleManaged)
        }

        if metalHud {
            builder.set("MTL_HUD_ENABLED", "1", layer: .bottleManaged)
        }

        if metalTrace {
            builder.set("METAL_CAPTURE_ENABLED", "1", layer: .bottleManaged)
        }

        if avxEnabled {
            builder.set("ROSETTA_ADVERTISE_AVX", "1", layer: .bottleManaged)
        }

        if dxrEnabled {
            builder.set("D3DM_SUPPORT_DXR", "1", layer: .bottleManaged)
        }

        // Metal validation - useful for debugging but can impact performance
        if metalValidation {
            builder.set("MTL_DEBUG_LAYER", "1", layer: .bottleManaged)
        }

        // macOS Sequoia compatibility mode (whisky-app/whisky#1310, #1372)
        // Applies additional fixes for graphics and launcher issues on macOS 15.x
        // Since macOS 15 is now the minimum deployment target, we only check the setting
        if sequoiaCompatMode {
            // Disable problematic Metal shader validation on Sequoia
            // This helps fix graphics corruption issues (whisky-app/whisky#1310)
            builder.set("MTL_DEBUG_LAYER", "0", layer: .bottleManaged)

            // Stability improvements for D3DMetal on macOS 15.x
            builder.set("D3DM_VALIDATION", "0", layer: .bottleManaged)

            // Help with Steam and launcher compatibility (whisky-app/whisky#1307, #1372)
            // Disable Wine's fsync which has issues on Sequoia
            builder.set("WINEFSYNC", "0", layer: .bottleManaged)
        }

        // Performance preset handling (whisky-app/whisky#1361 - FPS regression fix)
        populatePerformancePreset(builder: &builder)

        // Shader cache control
        if !shaderCacheEnabled {
            builder.set("DXVK_SHADER_COMPILE_THREADS", "1", layer: .bottleManaged)
            builder.set("__GL_SHADER_DISK_CACHE", "0", layer: .bottleManaged)
        }

        // Force D3D11 mode - helps with compatibility (whisky-app/whisky#1361)
        if forceD3D11 {
            builder.set("D3DM_FORCE_D3D11", "1", layer: .bottleManaged)
            builder.set("D3DM_FEATURE_LEVEL_12_0", "0", layer: .bottleManaged)
        }

        return managedDLLOverrides
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    /// Populates the ``EnvironmentLayer/launcherManaged`` layer with launcher compatibility fixes.
    ///
    /// This method implements the dual-mode launcher compatibility system from frankea/Whisky#41:
    /// - Merges launcher-specific environment overrides
    /// - Applies locale fixes for steamwebhelper crashes
    /// - Configures GPU spoofing for launcher checks
    /// - Sets network timeouts for download reliability
    ///
    /// - Parameter builder: The environment builder to populate.
    /// - Returns: Launcher-required DLL override entries with their sources.
    public func populateLauncherManagedLayer(
        builder: inout EnvironmentBuilder
    ) -> [(entry: DLLOverrideEntry, source: DLLOverrideSource)] {
        var launcherDLLOverrides: [(entry: DLLOverrideEntry, source: DLLOverrideSource)] = []

        guard launcherCompatibilityMode else { return launcherDLLOverrides }

        // Track whether the launcher preset provides a locale
        var launcherProvidesLocale = false

        // Apply launcher-specific environment overrides if launcher detected
        if let launcher = detectedLauncher {
            let launcherEnv = launcher.environmentOverrides()
            builder.setAll(launcherEnv, layer: .launcherManaged)
            launcherProvidesLocale = launcherEnv["LC_ALL"] != nil

            // Auto-enable DXVK DLL overrides if launcher requires it
            if autoEnableDXVK, launcher.requiresDXVK {
                for entry in DLLOverrideResolver.dxvkPreset {
                    launcherDLLOverrides.append((entry: entry, source: .launcher(launcher.displayName)))
                }
            }
        }

        // Apply locale override if specified (not using launcher default)
        // Defensive: Also check rawValue is not empty to prevent setting LC_ALL/LANG to ""
        // Only apply if launcher preset didn't already set LC_ALL (preserves launcher optimization)
        if launcherLocale != .auto, !launcherLocale.rawValue.isEmpty, !launcherProvidesLocale {
            builder.set("LC_ALL", launcherLocale.rawValue, layer: .launcherManaged)
            builder.set("LANG", launcherLocale.rawValue, layer: .launcherManaged)
            // Force C locale for date/time parsing to avoid ICU issues
            builder.set("LC_TIME", "C", layer: .launcherManaged)
            builder.set("LC_NUMERIC", "C", layer: .launcherManaged)
        }
        // Note: If launcher preset already set LC_ALL (e.g., Steam sets "en_US.UTF-8"),
        // we don't overwrite it. This preserves launcher-optimized locale strings.

        // Apply GPU spoofing if enabled
        if gpuSpoofing {
            let gpuEnv = GPUDetection.spoofWithVendor(gpuVendor)
            let launcherEnv = detectedLauncher?.environmentOverrides() ?? [:]
            // Don't override values already set by launcher preset (original behavior:
            // merge with "current.isEmpty ? new : current")
            for (key, value) in gpuEnv {
                let existing = launcherEnv[key]
                if existing == nil || (existing?.isEmpty ?? true) {
                    builder.set(key, value, layer: .launcherManaged)
                }
            }
        }

        // Network timeout configuration
        // Applied if user customized timeout (including launcher-set values)
        // Launcher-specific timeouts are set via bottle.settings.networkTimeout by
        // LauncherDetection.applyLauncherFixes(), giving users control via UI slider
        if networkTimeout != 60_000 { // If not default (60s)
            builder.set("WINHTTP_CONNECT_TIMEOUT", String(networkTimeout), layer: .launcherManaged)
            builder.set("WINHTTP_RECEIVE_TIMEOUT", String(networkTimeout * 2), layer: .launcherManaged)
        }

        // Connection pooling fixes for download stalls (whisky-app/whisky#1148, #1072, #1176)
        builder.set("WINE_MAX_CONNECTIONS_PER_SERVER", "10", layer: .launcherManaged)
        builder.set("WINE_FORCE_HTTP11", "1", layer: .launcherManaged) // HTTP/2 issues in Wine

        // SSL/TLS compatibility for launchers
        builder.set("WINE_ENABLE_SSL", "1", layer: .launcherManaged)
        builder.set("WINE_SSL_VERSION_MIN", "TLS1.2", layer: .launcherManaged)

        return launcherDLLOverrides
    }

    /// Populates the ``EnvironmentLayer/bottleManaged`` layer with controller/input compatibility fixes.
    ///
    /// Sets SDL environment variables to improve gamepad detection and functionality.
    /// See: https://wiki.libsdl.org/SDL2/CategoryHints (applies to both SDL2 and SDL3)
    ///
    /// - Parameter builder: The environment builder to populate.
    public func populateInputCompatibilityLayer(builder: inout EnvironmentBuilder) {
        guard controllerCompatibilityMode else { return }

        // Disable HIDAPI - forces SDL to use alternative input backend
        // May improve detection for controllers that don't work with HIDAPI
        if disableHIDAPI {
            builder.set("SDL_JOYSTICK_HIDAPI", "0", layer: .bottleManaged)
        }

        // Allow joystick events when app is in background
        // Useful for controller input when Wine window loses focus
        if allowBackgroundEvents {
            builder.set("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1", layer: .bottleManaged)
        }

        // Disable SDL to XInput mapping conversion
        // PlayStation/Switch controllers may show correct button mappings without this
        if disableControllerMapping {
            // Tell SDL not to remap controllers to XInput layout
            builder.set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", "1", layer: .bottleManaged)
        }
    }

    /// Populates performance preset environment variables into the bottleManaged layer.
    private func populatePerformancePreset(builder: inout EnvironmentBuilder) {
        switch performancePreset {
        case .balanced:
            // Default settings, no changes needed
            break

        case .performance:
            // Performance mode - prioritize FPS over visual quality (whisky-app/whisky#1361 fix)
            // Reduce D3DMetal shader quality for better performance
            builder.set("D3DM_FAST_SHADER_COMPILE", "1", layer: .bottleManaged)
            // Disable extra validation that can slow down rendering
            builder.set("D3DM_VALIDATION", "0", layer: .bottleManaged)
            builder.set("MTL_DEBUG_LAYER", "0", layer: .bottleManaged)
            // Enable DXVK async if not already enabled via the DXVK setting
            if !dxvkAsync {
                builder.set("DXVK_ASYNC", "1", layer: .bottleManaged)
            }
            // Use more aggressive shader compilation
            builder.set("DXVK_SHADER_OPT_LEVEL", "0", layer: .bottleManaged)
            // Reduce Metal resource tracking overhead
            builder.set("MTL_ENABLE_METAL_EVENTS", "0", layer: .bottleManaged)

        case .quality:
            // Quality mode - prioritize visuals over performance
            // Enable shader optimizations
            builder.set("DXVK_SHADER_OPT_LEVEL", "2", layer: .bottleManaged)
            // Disable fast shader compile for better quality
            builder.set("D3DM_FAST_SHADER_COMPILE", "0", layer: .bottleManaged)

        case .unity:
            // Unity games optimization (whisky-app/whisky#1313, #1312 - il2cpp fix)
            // Unity games often need specific memory and threading settings

            // Fix for il2cpp loading issues
            builder.set("MONO_THREADS_SUSPEND", "1", layer: .bottleManaged)
            // Increase file descriptor limit for Unity games
            builder.set("WINE_LARGE_ADDRESS_AWARE", "65536", layer: .bottleManaged)

            // Unity games often work better with D3D11
            if !forceD3D11 {
                builder.set("D3DM_FORCE_D3D11", "1", layer: .bottleManaged)
            }

            // Disable features that can cause issues with Unity's IL2CPP runtime
            builder.set("WINE_HEAP_REUSE", "0", layer: .bottleManaged)
            // Help with thread management for Unity's job system
            builder.set("WINE_DISABLE_NTDLL_THREAD_REGS", "1", layer: .bottleManaged)

            // Unity games may need more virtual memory
            builder.set("WINEPRELOADRESERVE", "1", layer: .bottleManaged)
        }
    }

    // MARK: - Deprecated Environment Variable API

    /// Populates a Wine environment dictionary based on these settings.
    ///
    /// - Parameter wineEnv: The environment dictionary to populate.
    ///   Existing values may be modified or removed based on settings.
    @available(*, deprecated, message: "Use EnvironmentBuilder layer populators instead")
    public func environmentVariables(wineEnv: inout [String: String]) {
        var builder = EnvironmentBuilder()

        // Call layer populators
        let managedOverrides = populateBottleManagedLayer(builder: &builder)
        let launcherOverrides = populateLauncherManagedLayer(builder: &builder)
        populateInputCompatibilityLayer(builder: &builder)

        // Resolve and merge
        let (resolved, _) = builder.resolve()

        // Handle explicit key removals that the builder encoded as nil entries.
        // Since resolve() omits removed keys, we must also remove them from the caller's dict.
        if enhancedSync == .none, MacOSVersion.current < .sequoia15_4 {
            wineEnv.removeValue(forKey: "WINEESYNC")
            wineEnv.removeValue(forKey: "WINEMSYNC")
        }

        // Merge resolved values into caller's dict (new values overwrite existing)
        wineEnv.merge(resolved) { _, new in new }

        // Compose WINEDLLOVERRIDES via DLLOverrideResolver
        let resolver = DLLOverrideResolver(
            managed: managedOverrides + launcherOverrides,
            bottleCustom: dllOverrides,
            programCustom: []
        )
        let (overrideString, _) = resolver.resolve()
        if !overrideString.isEmpty {
            wineEnv["WINEDLLOVERRIDES"] = overrideString
        }
    }
}

// swiftlint:enable type_body_length
