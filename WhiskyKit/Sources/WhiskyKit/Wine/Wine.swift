// swiftlint:disable file_length
//
//  Wine.swift
//  Whisky
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

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "Wine")

// swiftlint:disable type_body_length

/// The core interface for interacting with Wine on macOS.
///
/// The `Wine` class provides static methods for executing Wine processes, running Windows programs,
/// and managing Wine-related operations within a ``Bottle``. It handles environment configuration,
/// process management, and output streaming.
///
/// ## Overview
///
/// Wine is a compatibility layer that allows Windows applications to run on macOS. This class
/// abstracts the complexity of Wine process management and provides a Swift-friendly API.
///
/// ## Running Programs
///
/// To run a Windows executable:
///
/// ```swift
/// @MainActor
/// func launchGame(at url: URL, in bottle: Bottle) async throws {
///     try await Wine.runProgram(at: url, bottle: bottle)
/// }
/// ```
///
/// ## Wine Commands
///
/// Execute arbitrary Wine commands:
///
/// ```swift
/// @MainActor
/// func getWineVersion() async throws -> String {
///     return try await Wine.wineVersion()
/// }
/// ```
///
/// ## Thread Safety
///
/// Most public methods require `@MainActor` context because they interact with ``Bottle``
/// which is main-actor isolated.
///
/// ## Topics
///
/// ### Running Programs
/// - ``runProgram(at:args:bottle:environment:)``
/// - ``runWine(_:bottle:environment:)``
/// - ``runBatchFile(url:bottle:)``
///
/// ### Wine Processes
/// - ``runWineProcess(name:args:bottle:environment:)``
/// - ``runWineserverProcess(name:args:bottle:environment:)``
///
/// ### Utilities
/// - ``wineVersion()``
/// - ``killBottle(bottle:)``
/// - ``enableDXVK(bottle:)``
/// - ``generateRunCommand(at:bottle:args:environment:)``
/// - ``generateTerminalEnvironmentCommand(bottle:)``
public class Wine {
    /// URL to the installed DXVK folder containing Direct3D-to-Vulkan translation libraries.
    private static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
    /// URL to the installed DXMT payload containing Direct3D-11-to-Metal translation libraries.
    /// Absent on runtimes older than Wine Libraries 3.1.0.
    private static let dxmtFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXMT")
    /// The URL to the `wine64` binary executable.
    ///
    /// This is the main Wine binary used to execute Windows applications.
    /// The binary is located within the WhiskyWine installation directory.
    public static let wineBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wine64")
    /// URL to the `wineserver` binary for Wine server management.
    private static let wineserverBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wineserver")

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Runs a Wine process with the given arguments and returns a stream of output.
    ///
    /// This method executes the Wine binary with the specified arguments within the context
    /// of a bottle. The bottle's settings are used to configure the Wine environment.
    ///
    /// - Parameters:
    ///   - name: An optional descriptive name for the process, used in logging.
    ///   - args: The command-line arguments to pass to Wine.
    ///   - bottle: The ``Bottle`` context in which to run the process.
    ///   - environment: Additional environment variables to set for this process.
    /// - Returns: An `AsyncStream` of ``ProcessOutput`` containing stdout, stderr, and lifecycle events.
    /// - Throws: An error if the process cannot be started.
    @MainActor
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        let wineEnvironment = constructWineEnvironment(for: bottle, environment: environment)

        return try runProcess(
            name: name, args: args, environment: wineEnvironment, executableURL: wineBinary,
            fileHandle: fileHandle
        )
    }

    /// Runs a Wine server process with the given arguments and returns a stream of output.
    ///
    /// The Wine server manages shared resources and state for all Wine processes in a bottle.
    /// This method is typically used for administrative operations like killing all processes.
    ///
    /// - Parameters:
    ///   - name: An optional descriptive name for the process, used in logging.
    ///   - args: The command-line arguments to pass to wineserver.
    ///   - bottle: The ``Bottle`` context in which to run the server process.
    ///   - environment: Additional environment variables to set for this process.
    /// - Returns: An `AsyncStream` of ``ProcessOutput`` containing stdout, stderr, and lifecycle events.
    /// - Throws: An error if the process cannot be started.
    @MainActor
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        let wineserverEnvironment = constructWineEnvironment(for: bottle, environment: environment)

        return try runProcess(
            name: name, args: args, environment: wineserverEnvironment, executableURL: wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Runs a Windows executable within a Wine bottle.
    ///
    /// This is the primary method for launching Windows applications. It handles DXVK setup
    /// if enabled in the bottle settings and executes the program using `wine start /unix`.
    ///
    /// - Note: If DXVK is enabled in the bottle's settings (`bottle.settings.dxvk`),
    ///   the DXVK libraries will be automatically installed into the bottle before
    ///   execution. This ensures Direct3D games use Vulkan translation for better
    ///   performance on macOS.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @MainActor
    /// func launchGame() async throws {
    ///     let gameURL = bottle.url
    ///         .appendingPathComponent("drive_c")
    ///         .appendingPathComponent("Games")
    ///         .appendingPathComponent("MyGame.exe")
    ///
    ///     try await Wine.runProgram(at: gameURL, bottle: bottle)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable (.exe) file.
    ///   - args: Optional command-line arguments to pass to the program.
    ///   - bottle: The ``Bottle`` in which to run the program.
    ///   - environment: Additional environment variables for this execution.
    ///   - programOverrides: Optional per-program setting overrides. `nil` fields inherit from bottle.
    /// - Throws: An error if the program cannot be started or Wine encounters an error.
    /// Result of a Wine program run, providing the exit code and log file URL
    /// for post-run diagnostics.
    public struct ProgramRunResult: Sendable {
        /// The exit code from the `wine start` process.
        public let exitCode: Int32
        /// URL to the log file created for this run.
        public let logFileURL: URL
        /// The UUID of the run log entry created for this run.
        ///
        /// Use this to correlate the run result with the run log history
        /// entry, e.g., to open the correct log entry in the console UI.
        public let runLogEntryId: UUID
    }

    // swiftlint:disable function_body_length
    @discardableResult
    @MainActor
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:],
        programOverrides: ProgramOverrides? = nil, programSettings: ProgramSettings? = nil,
        gameProfileEnvironment: [String: String] = [:],
        overridesApplyToDescendants: Bool = false
    ) async throws -> ProgramRunResult {
        // Note: Launcher detection and fix application happen before this method
        // is called, via LauncherFixes.detectAndApply from the app's run paths
        // (FileOpenView/BottleView/ProgramMenuView).

        // The effective backend for this launch: a program-level override wins
        // over the bottle setting, and `.recommended` resolves to its concrete
        // backend. This decides which translation layer's files are deployed;
        // the matching WINEDLLOVERRIDES come from the environment layers.
        // `.recommended` resolves against what is being launched, not just the
        // machine.
        let effectiveBackendChoice = programOverrides?.graphicsBackend ?? bottle.settings.graphicsBackend
        let effectiveBackend = effectiveBackendChoice == .recommended
            ? GraphicsBackendResolver.resolve(for: LauncherType.detect(from: url))
            : effectiveBackendChoice

        // The bottle composes its overrides from its own resolution, which does
        // not know what is being launched, so pin the decision here or a
        // steered launcher gets DXVK's files and none of its overrides.
        var programOverrides = programOverrides
        if effectiveBackendChoice == .recommended, effectiveBackend != GraphicsBackendResolver.resolve() {
            var pinned = programOverrides ?? ProgramOverrides()
            pinned.graphicsBackend = effectiveBackend
            programOverrides = pinned
        }

        try prepareBackendPrefix(effectiveBackend, bottle: bottle)

        // Enable DXVK if needed: effective backend, the legacy program-level
        // flag (honored only without a backend override, mirroring
        // applyProgramOverrides), or launcher auto-enable.
        let legacyProgramDXVK = programOverrides?.graphicsBackend == nil && programOverrides?.dxvk == true
        let shouldEnableDXVK = effectiveBackend == .dxvk || legacyProgramDXVK ||
            (bottle.settings.autoEnableDXVK &&
                bottle.settings.detectedLauncher?.requiresDXVK == true)

        if shouldEnableDXVK {
            try enableDXVK(bottle: bottle)
        }

        // Disable App Nap if requested to prevent macOS from throttling Wine processes.
        // Note: This token is held while the `wine start` launcher process runs. The actual
        // game process continues as a child of wineserver after the launcher exits. Full
        // App Nap prevention for the entire game session would require tracking wineserver,
        // but this provides protection during the critical startup/initialization phase.
        let activityToken: NSObjectProtocol? = bottle.settings.disableAppNap
            ? ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Wine process running for \(bottle.settings.name)"
            )
            : nil
        defer {
            if let token = activityToken {
                ProcessInfo.processInfo.endActivity(token)
            }
        }

        // Build the Wine environment with program overrides flowing through the programUser layer
        let (fileHandle, logFileURL) = try makeFileHandleWithURL()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)

        var wineEnvironment = constructWineEnvironment(
            for: bottle, environment: environment, programOverrides: programOverrides,
            programSettings: programSettings, gameProfileEnvironment: gameProfileEnvironment
        )

        try await applyDLLOverrides(
            for: url, bottle: bottle,
            wineEnvironment: &wineEnvironment,
            applyToDescendants: overridesApplyToDescendants
        )

        // Create a run log entry to track this session
        let programName = url.lastPathComponent
        var runLogEntry = RunLogEntry(programName: programName, logFileName: logFileURL.lastPathComponent)

        // Record the active WINEDEBUG preset if one is set
        if wineEnvironment.keys.contains("WINEDEBUG") {
            runLogEntry.activeWineDebugPreset = programSettings?.activeWineDebugPreset?.rawValue
        }

        // Persist the "running" state immediately
        var runLogHistory = RunLogStore.load(for: programName, in: bottle.url)
        let prunedEntries = runLogHistory.append(runLogEntry)
        RunLogStore.save(runLogHistory, for: programName, in: bottle.url)

        // Clean up log files for pruned entries
        for pruned in prunedEntries {
            let prunedLogURL = Self.logsFolder.appending(path: pruned.logFileName)
            try? FileManager.default.removeItem(at: prunedLogURL)
        }

        // Build launch arguments with optional per-program virtual desktop
        let launchArgs: [String]
        if let overrides = programOverrides,
           let vdEnabled = overrides.virtualDesktopEnabled, vdEnabled {
            let resolution = Self.resolveVirtualDesktopResolution(from: overrides)
            let desktopName = programName.replacingOccurrences(of: " ", with: "_")
            launchArgs = [
                "explorer", "/desktop=\(desktopName),\(resolution)",
                url.path(percentEncoded: false)
            ] + args
        } else {
            launchArgs = ["start", "/unix", url.path(percentEncoded: false)] + args
        }

        var exitCode: Int32 = 0
        for await output in try runProcess(
            name: programName,
            args: launchArgs,
            environment: wineEnvironment, executableURL: wineBinary,
            fileHandle: fileHandle
        ) {
            if case let .terminated(code) = output {
                exitCode = code
            }
        }

        // Update the run log entry with exit information
        var updatedHistory = RunLogStore.load(for: programName, in: bottle.url)
        updatedHistory.markCompleted(
            id: runLogEntry.id,
            exitCode: exitCode,
            hasWineDebug: wineEnvironment.keys.contains("WINEDEBUG")
        )
        RunLogStore.save(updatedHistory, for: programName, in: bottle.url)

        return ProgramRunResult(exitCode: exitCode, logFileURL: logFileURL, runLogEntryId: runLogEntry.id)
    }

    // swiftlint:enable function_body_length

    /// Resolves the virtual desktop resolution string from per-program overrides.
    ///
    /// - Parameter overrides: The program overrides containing display settings.
    /// - Returns: A resolution string like `"1920x1080"`.
    private static func resolveVirtualDesktopResolution(from overrides: ProgramOverrides) -> String {
        let preset = overrides.resolutionPreset ?? .r1920x1080
        if let dims = preset.dimensions {
            return "\(dims.width)x\(dims.height)"
        }
        if preset == .custom {
            let width = overrides.customResolutionWidth ?? 1_920
            let height = overrides.customResolutionHeight ?? 1_080
            return "\(width)x\(height)"
        }
        // matchDisplay fallback
        return "1920x1080"
    }

    /// Generates a shell command string for running a Windows program.
    ///
    /// This method creates a complete shell command that can be copied to a terminal
    /// or used in scripts. It includes all necessary environment variables and properly
    /// escapes arguments to prevent shell injection.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable.
    ///   - bottle: The ``Bottle`` configuration to use.
    ///   - args: Additional arguments as a single string.
    ///   - environment: Custom environment variables.
    ///   - preEscaped: If true, args are already shell-escaped and won't be escaped again.
    ///     Use this when passing an array of arguments that were individually escaped.
    /// - Returns: A shell-safe command string ready for execution.
    @MainActor
    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String], preEscaped: Bool = false
    ) -> String {
        // Escape args and environment values to prevent shell injection from user-editable settings
        let escapedArgs = preEscaped ? args : args.esc
        var wineCmd = "\(wineBinary.esc) start /unix \(url.esc) \(escapedArgs)"
        let wineEnv = constructWineEnvironment(for: bottle, environment: environment)
        for envVar in wineEnv {
            if isValidEnvKey(envVar.key) {
                // Keys are validated to be safe shell identifiers; values are escaped
                // Note: No quotes needed - .esc handles all shell metacharacter escaping
                wineCmd = "\(envVar.key)=\(envVar.value.esc) " + wineCmd
            } else {
                logger.debug("Skipping invalid environment key '\(envVar.key)' in generateRunCommand")
            }
        }

        return wineCmd
    }

    /// Generates shell commands to configure a terminal session for Wine development.
    ///
    /// The generated commands set up the PATH, create convenient aliases for Wine tools,
    /// and export all necessary environment variables for the given bottle.
    ///
    /// ## Usage
    ///
    /// Copy the output to your terminal to enable Wine commands:
    ///
    /// ```bash
    /// # After running the generated commands, you can use:
    /// wine myprogram.exe
    /// winecfg
    /// regedit
    /// ```
    ///
    /// - Parameter bottle: The ``Bottle`` to configure the environment for.
    /// - Returns: A multi-line string of shell export commands and aliases.
    @MainActor
    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        var cmd = """
        export PATH=\"\(WhiskyWineInstaller.binFolder.path.esc):$PATH\"
        export WINE=\"wine64\"
        alias wine=\"wine64\"
        alias winecfg=\"wine64 winecfg\"
        alias msiexec=\"wine64 msiexec\"
        alias regedit=\"wine64 regedit\"
        alias regsvr32=\"wine64 regsvr32\"
        alias wineboot=\"wine64 wineboot\"
        alias wineconsole=\"wine64 wineconsole\"
        alias winedbg=\"wine64 winedbg\"
        alias winefile=\"wine64 winefile\"
        alias winepath=\"wine64 winepath\"
        """

        let env = constructWineEnvironment(for: bottle)
        for envVar in env {
            if isValidEnvKey(envVar.key) {
                // Keys are validated to be safe shell identifiers; values are escaped
                cmd += "\nexport \(envVar.key)=\"\(envVar.value.esc)\""
            } else {
                logger.debug("Skipping invalid environment key '\(envVar.key)' in generateTerminalEnvironmentCommand")
            }
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    @MainActor
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case let .message(message), let .error(message):
                return message
            }
        }.joined()
    }

    /// Runs a Wine command and returns the collected output as a string.
    ///
    /// This method executes Wine with the given arguments and waits for completion,
    /// collecting all output into a single string. Use this for commands where you
    /// need the complete result, such as queries or configuration commands.
    ///
    /// - Parameters:
    ///   - args: The command-line arguments to pass to Wine.
    ///   - bottle: Optional ``Bottle`` context. If `nil`, runs without a bottle prefix.
    ///   - environment: Additional environment variables.
    /// - Returns: The combined stdout and stderr output from the Wine process.
    /// - Throws: An error if the process cannot be started.
    ///
    /// - Note: This overload maintains backward compatibility with optional Bottle parameter.
    @discardableResult
    @MainActor
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        if let bottle {
            try await runWineWithBottle(args, bottle: bottle, environment: environment)
        } else {
            try await runWineWithoutBottle(args, environment: environment)
        }
    }

    /// Run a `wine` command with the given arguments and a bottle context
    @discardableResult
    @MainActor
    private static func runWineWithBottle(
        _ args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()
        fileHandle.writeInfo(for: bottle)
        let wineEnvironment = constructWineEnvironment(for: bottle, environment: environment)

        for await output in try runWineProcess(args: args, environment: wineEnvironment, fileHandle: fileHandle) {
            switch output {
            case .started, .terminated:
                break
            case let .message(message), let .error(message):
                result.append(message)
            }
        }

        return result.joined()
    }

    /// Run a `wine` command without a bottle context (e.g., for --version queries)
    @discardableResult
    @MainActor
    private static func runWineWithoutBottle(
        _ args: [String], environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicationInfo()

        for await output in try runWineProcess(args: args, environment: environment, fileHandle: fileHandle) {
            switch output {
            case .started, .terminated:
                break
            case let .message(message), let .error(message):
                result.append(message)
            }
        }

        return result.joined()
    }

    /// Returns the version string of the installed Wine binary.
    ///
    /// This queries Wine for its version and parses the result into a clean version string.
    /// Handles various Wine version formats including CrossOver Wine (WineCX).
    ///
    /// ## Example
    ///
    /// ```swift
    /// @MainActor
    /// func displayVersion() async throws {
    ///     let version = try await Wine.wineVersion()
    ///     print("Wine version: \(version)")  // e.g., "9.0"
    /// }
    /// ```
    ///
    /// - Returns: The Wine version string (e.g., "9.0", "8.0.2").
    /// - Throws: An error if Wine cannot be executed.
    @MainActor
    public static func wineVersion() async throws -> String {
        var output = try await runWineWithoutBottle(["--version"])
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Executes a Windows batch file (.bat or .cmd) within a bottle.
    ///
    /// This runs the batch file using `cmd /c` through Wine, allowing execution
    /// of Windows batch scripts for installation or configuration tasks.
    ///
    /// - Parameters:
    ///   - url: The URL to the batch file.
    ///   - bottle: The ``Bottle`` in which to run the script.
    /// - Returns: The output from the batch file execution.
    /// - Throws: An error if execution fails.
    @discardableResult
    @MainActor
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    /// Terminates all Wine processes running in a bottle.
    ///
    /// This sends a kill signal to the bottle's Wine server, which terminates all
    /// associated processes. The operation is fire-and-forget: errors are logged
    /// but not propagated to the caller.
    ///
    /// Use this to forcefully stop all programs in a bottle, for example when
    /// a game becomes unresponsive.
    ///
    /// - Parameter bottle: The ``Bottle`` whose processes should be terminated.
    /// - Note: This is intentionally non-blocking. Errors are logged but not propagated.
    @MainActor
    public static func killBottle(bottle: Bottle) {
        Task {
            do {
                _ = try await runWineserver(["-k"], bottle: bottle)
            } catch {
                Logger.wineKit.error("Failed to kill bottle '\(bottle.settings.name)': \(error.localizedDescription)")
            }
        }
    }

    /// Installs DXVK libraries into a bottle's Windows system directories.
    ///
    /// DXVK translates DirectX 9/10/11 calls to Vulkan, often providing better
    /// performance than Wine's built-in DirectX implementation. This method copies
    /// the DXVK DLL files to the bottle's system32 and syswow64 directories.
    ///
    /// - Parameter bottle: The ``Bottle`` to install DXVK into.
    /// - Throws: An error if the DLL files cannot be copied.
    ///
    /// - Note: This is automatically called by ``runProgram(at:args:bottle:environment:)``
    ///   when DXVK is enabled in the bottle settings.
    @MainActor
    public static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// Errors thrown by ``enableDXMT(bottle:)``.
    public enum DXMTError: LocalizedError, Equatable {
        /// The installed runtime has no usable DXMT payload — either absent
        /// (a runtime predating the DXMT payload, or a damaged/truncated
        /// install) or the older builtin-variant payload that cannot be
        /// activated per-bottle.
        case payloadMissing

        public var errorDescription: String? {
            switch self {
            case .payloadMissing:
                String(localized: "wine.dxmt.error.payloadMissing")
            }
        }
    }

    /// DXMT's D3D translation trio — native PEs loaded from the prefix under the
    /// `n,b` override.
    private static let dxmtNativeTrio = ["d3d11.dll", "dxgi.dll", "d3d10core.dll"]

    /// The DXMT files deployed into a bottle: the native D3D trio plus
    /// `winemetal.dll`. `winemetal.dll` is the builtin-marked redirect whose
    /// import resolves to the runtime's `winemetal.dll` builtin in `lib/wine`.
    /// The NVIDIA extras (nvapi64/nvngx) in the payload are deliberately not
    /// deployed — DXMT's vendor spoofing is out of scope.
    private static let dxmtPrefixDLLs = dxmtNativeTrio + ["winemetal.dll"]

    /// Whether the installed runtime carries a DXMT payload that can actually be
    /// activated per-bottle: present **and** the *native* variant. A
    /// builtin-marked trio (the older runtime layout) is silently ignored by the
    /// loader in favor of wined3d, so it does not count as available. Used to
    /// gate the DXMT backend in the pickers. The x64 `d3d11.dll` is sampled as
    /// the trio's representative (the runtime assembles all three together); the
    /// per-launch ``enableDXMT(payloadRoot:prefixRoot:)`` guard verifies the whole
    /// trio.
    public static func isDXMTRuntimeNative() -> Bool {
        isDXMTRuntimeNative(payloadRoot: dxmtFolder)
    }

    /// Capability check against an explicit payload root. Factored out so the
    /// gate can be tested against temporary fixtures (mirrors the
    /// ``enableDXMT(payloadRoot:prefixRoot:)`` seam).
    static func isDXMTRuntimeNative(payloadRoot: URL) -> Bool {
        let d3d11 = payloadRoot.appending(path: "x64").appending(path: "d3d11.dll")
        guard FileManager.default.fileExists(atPath: d3d11.path(percentEncoded: false)) else { return false }
        return (try? isNativePE(d3d11)) ?? false
    }

    /// Returns `true` when the PE at `url` is a markerless *native* DLL — i.e. its
    /// DOS stub does not carry winebuild's "Wine builtin DLL" signature in the 16
    /// bytes at offset 0x40. A builtin-marked copy placed in the prefix is ignored
    /// by the loader, which redirects to the `lib/wine` builtin (wined3d) instead.
    /// A file too short to hold those 16 bytes is treated as **not** native
    /// (fail-closed): a truncated or corrupt payload must not be deployed as if it
    /// were a working native DLL — that would resurrect the silent wined3d
    /// fallback this guard exists to prevent.
    static func isNativePE(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0x40)
        guard let marker = try handle.read(upToCount: 16), marker.count == 16 else {
            return false
        }
        return marker != Data("Wine builtin DLL".utf8)
    }

    /// Places the per-bottle files a backend needs in the prefix before launch.
    ///
    /// DXMT goes first: if launcher auto-DXVK also fires in `runProgram`, DXVK's
    /// file copy deterministically wins, matching the override-layer order where
    /// launcher-managed entries land after bottle-managed ones.
    @MainActor
    private static func prepareBackendPrefix(_ backend: GraphicsBackend, bottle: Bottle) throws {
        switch backend {
        case .dxmt:
            try enableDXMT(bottle: bottle)
        case .d3dMetal, .dxvk, .wined3d, .recommended:
            break
        }

        applyMetalFX(bottle: bottle, backend: backend)
    }

    /// Opts a bottle in or out of D3DMetal's DLSS-to-MetalFX path, per
    /// ``BottleSettings/metalFX`` and the backend the launch actually resolved
    /// to.
    ///
    /// The bridge itself is a builtin in the shared Wine tree, so it cannot be
    /// installed per bottle. What can is the `system32` entry the loader needs
    /// before it will look in the builtin directory at all: without one,
    /// `LoadLibrary("nvngx.dll")` fails with `ERROR_MOD_NOT_FOUND` however
    /// complete the tree is. So the placeholder is the switch: present means a
    /// game can reach MetalFX, absent means the bridge is inert.
    ///
    /// Only D3DMetal implements the DLSS entry points behind it, so every other
    /// backend clears, setting or no setting. Otherwise a bottle switched away
    /// from D3DMetal with MetalFX still on keeps a placeholder for a bridge
    /// nothing in that prefix can answer, and a DLSS-aware game reaches it under
    /// a backend it was never meant for.
    ///
    /// - Parameters:
    ///   - bottle: The ``Bottle`` whose opt-in state to apply.
    ///   - backend: The backend this launch resolved to.
    ///   - libraryFolder: The runtime tree holding the bridge.
    ///
    /// - Note: Called by `runProgram` for every launch, in both directions, so
    ///   turning the setting off or switching backend takes effect on the next
    ///   launch without the user having to repair anything.
    @MainActor
    public static func applyMetalFX(
        bottle: Bottle,
        backend: GraphicsBackend,
        libraryFolder: URL = WhiskyWineInstaller.libraryFolder
    ) {
        if backend == .d3dMetal, bottle.settings.metalFX {
            GPTKImporter.seedMetalFXBridgePlaceholder(inBottle: bottle.url, fromLibraryFolder: libraryFolder)
            seedNGXModelConfig(inBottle: bottle.url)
        } else {
            GPTKImporter.clearMetalFXBridgePlaceholder(inBottle: bottle.url)
        }
    }

    /// Where NGX keeps the manifest its updater reads, which a real NVIDIA driver
    /// would have written.
    static let ngxModelConfigPath = ["drive_c", "ProgramData", "NVIDIA", "NGX", "models"]

    /// Writes the NGX manifest a driver install would leave behind.
    ///
    /// Streamline opens this before it does anything else and logs a pair of
    /// errors per launch when it is missing:
    ///
    ///     [streamline][error] File 'C:\ProgramData/NVIDIA/NGX/models/nvngx_config.txt' does not exist
    ///     [streamline][error] readServerManifest: Failed to open manifest file
    ///
    /// Only the over-the-air updater reads what is inside, and that updater
    /// (`nvngx_update.exe`) does not exist here either, so the contents matter
    /// less than the file existing. Left alone once written, so a real one from a
    /// driver install or a user's own edit survives.
    ///
    /// - Parameter bottle: The bottle whose prefix to seed.
    static func seedNGXModelConfig(inBottle bottle: URL) {
        let fileManager = FileManager.default
        let folder = ngxModelConfigPath.reduce(bottle) { $0.appending(path: $1) }
        let config = folder.appending(path: "nvngx_config.txt")
        guard !fileManager.fileExists(atPath: config.path(percentEncoded: false)) else { return }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try? "[global]\nversion = 1\n".write(to: config, atomically: true, encoding: .utf8)
    }

    /// Installs DXMT into a bottle so its Direct3D-11-to-Metal layer is used.
    ///
    /// Copies the native D3D translation trio (`d3d11`, `dxgi`, `d3d10core`) and
    /// `winemetal.dll` from the runtime's DXMT payload into the bottle's system
    /// directories — the same per-bottle, prefix-local model as ``enableDXVK``,
    /// selected by the `n,b` overrides from ``DLLOverrideResolver/dxmtPreset``.
    /// The runtime ships DXMT's `winemetal.dll` builtin (paired with its
    /// `winemetal.so` unixlib) in `lib/wine`, so this method never touches the
    /// shared Wine tree; the prefix `winemetal.dll` is the builtin-marked
    /// redirect that resolves the trio's import to that builtin.
    ///
    /// - Parameter bottle: The ``Bottle`` to install DXMT into.
    /// - Throws: ``DXMTError/payloadMissing`` when the runtime has no usable
    ///   (present and native) DXMT payload, or a `CocoaError` if a copy fails.
    ///
    /// - Note: This is automatically called by `runProgram` when the effective
    ///   graphics backend is `.dxmt`.
    @MainActor
    public static func enableDXMT(bottle: Bottle) throws {
        try enableDXMT(payloadRoot: Wine.dxmtFolder, prefixRoot: bottle.url)
    }

    /// Performs the DXMT installation against explicit roots. Factored out of
    /// ``enableDXMT(bottle:)`` so the file placement can be tested against
    /// temporary directories (mirrors `enableDXVK`'s prefix-local copy).
    static func enableDXMT(payloadRoot: URL, prefixRoot: URL) throws {
        let fileManager = FileManager.default
        let x64Payload = payloadRoot.appending(path: "x64")
        let x32Payload = payloadRoot.appending(path: "x32")

        let windowsDir = prefixRoot.appending(path: "drive_c").appending(path: "windows")
        let system32 = windowsDir.appending(path: "system32")
        let syswow64 = windowsDir.appending(path: "syswow64")
        let deploy32Bit = fileManager.fileExists(atPath: syswow64.path(percentEncoded: false))

        // Validate every source BEFORE touching the prefix, and require the whole
        // trio to be the native variant. A damaged runtime (a file missing or
        // truncated) or the older builtin-variant payload (which the loader would
        // ignore in favor of wined3d) must fail with the actionable payloadMissing
        // error rather than half-deploy, or launch a bottle that silently isn't
        // using DXMT.
        var sources = dxmtPrefixDLLs.map { x64Payload.appending(path: $0) }
        if deploy32Bit {
            sources += dxmtPrefixDLLs.map { x32Payload.appending(path: $0) }
        }
        let allPresent = sources.allSatisfy { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
        let trioIsNative = dxmtNativeTrio.allSatisfy {
            (try? isNativePE(x64Payload.appending(path: $0))) == true
        }
        guard allPresent, trioIsNative else {
            throw DXMTError.payloadMissing
        }

        for name in dxmtPrefixDLLs {
            try fileManager.installFileIfContentDiffers(
                at: system32.appending(path: name),
                from: x64Payload.appending(path: name)
            )
        }

        // 32-bit half: only when the prefix actually has a syswow64 tree.
        if deploy32Bit {
            for name in dxmtPrefixDLLs {
                try fileManager.installFileIfContentDiffers(
                    at: syswow64.appending(path: name),
                    from: x32Payload.appending(path: name)
                )
            }
        }
    }
}

// MARK: - Environment Key Validation

extension Wine {
    /// Reinitializes a Wine prefix to repair missing user directories.
    ///
    /// This method runs `wineboot --init` to reinitialize the Wine prefix,
    /// which creates any missing user profile directories that may have been
    /// deleted or never properly created during initial bottle setup.
    ///
    /// Use this method when winetricks or other dependency installations fail
    /// due to missing `%AppData%` or user profile directories.
    ///
    /// - Parameter bottle: The ``Bottle`` whose prefix should be repaired.
    /// - Throws: An error if wineboot fails to initialize the prefix.
    ///
    /// - Note: This operation may take several seconds as Wine reinitializes
    ///   the prefix and creates missing directories.
    @discardableResult
    @MainActor
    public static func repairPrefix(bottle: Bottle) async throws -> String {
        logger.info("Repairing Wine prefix for bottle '\(bottle.settings.name)'")
        return try await runWine(["wineboot", "--init"], bottle: bottle)
    }

    /// Checks if an environment variable key is a valid POSIX shell identifier.
    ///
    /// Valid names must start with an ASCII letter or underscore, followed by
    /// any combination of ASCII letters, digits, or underscores.
    /// This prevents shell injection through malicious environment variable keys.
    ///
    /// - Note: Uses explicit ASCII checks rather than Swift's Unicode-aware
    ///   `isLetter`/`isNumber` methods, since POSIX shells only accept ASCII
    ///   identifiers (`[A-Za-z_][A-Za-z0-9_]*`).
    ///
    /// - Parameter key: The environment variable name to validate.
    /// - Returns: `true` if the key is safe to use in shell commands.
    static func isValidEnvKey(_ key: String) -> Bool {
        guard let first = key.first else { return false }
        guard isAsciiLetter(first) || first == "_" else { return false }
        return key.allSatisfy { isAsciiLetter($0) || isAsciiDigit($0) || $0 == "_" }
    }

    /// Checks if a character is an ASCII letter (A-Z, a-z).
    static func isAsciiLetter(_ char: Character) -> Bool {
        guard let ascii = char.asciiValue else { return false }
        return (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122) // A-Z or a-z
    }

    /// Checks if a character is an ASCII digit (0-9).
    static func isAsciiDigit(_ char: Character) -> Bool {
        guard let ascii = char.asciiValue else { return false }
        return ascii >= 48 && ascii <= 57 // 0-9
    }
}

/// Errors that can occur during Wine interface operations.
enum WineInterfaceError: Error {
    /// The response from Wine was invalid or could not be parsed.
    case invalidResponse
}

// MARK: - Logging Support

public extension Wine {
    /// Maximum size of a single Whisky log file written by Wine process logging.
    ///
    /// Policy: cap each individual log at 20 MiB.
    static let maxLogFileBytes: Int64 = 20 * 1_024 * 1_024

    /// Maximum total size allowed for all Whisky log files in `logsFolder`.
    ///
    /// Policy: cap total disk usage of Whisky's log directory at 200 MiB.
    static let maxLogsFolderBytes: Int64 = 200 * 1_024 * 1_024

    /// Marker appended once when file logging begins truncation.
    ///
    /// - Important: This marker is written at most once per log file and counts toward `maxLogFileBytes`.
    static let logTruncationMarker = "\n[Whisky] Log truncated: reached 20 MiB cap; further output discarded.\n"

    /// The URL to the directory where Wine process logs are stored.
    ///
    /// Logs are stored in `~/Library/Logs/{bundle-identifier}/` with ISO 8601
    /// timestamps as filenames.
    static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.whiskyBundleIdentifier)

    /// Enforces log retention policy by deleting the oldest `.log` files until total size is under the limit.
    ///
    /// - Important: This method only operates on the provided folder and only deletes regular files with a `.log`
    ///   extension. It is intentionally best-effort: errors are logged but do not throw.
    static func enforceLogRetention(in folder: URL, maxTotalBytes: Int64) {
        do {
            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .contentModificationDateKey,
                .creationDateKey,
                .fileSizeKey
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )

            struct LogFile {
                let url: URL
                let size: Int64
                let date: Date
            }

            var files: [LogFile] = []
            files.reserveCapacity(urls.count)

            for url in urls {
                guard url.pathExtension.lowercased() == "log" else { continue }
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.fileSize ?? 0)
                let date = values.contentModificationDate ?? values.creationDate ?? .distantPast
                files.append(LogFile(url: url, size: size, date: date))
            }

            var total: Int64 = files.reduce(0) { $0 + $1.size }
            guard total > maxTotalBytes else { return }

            // Oldest first
            files.sort { $0.date < $1.date }

            for file in files {
                guard total > maxTotalBytes else { break }
                do {
                    try FileManager.default.removeItem(at: file.url)
                    total -= file.size
                } catch {
                    let logPath = file.url.path(percentEncoded: false)
                    let errorDescription = error.localizedDescription
                    Logger.wineKit.error(
                        "Failed to remove log \(logPath, privacy: .public): \(errorDescription, privacy: .public)"
                    )
                }
            }
        } catch {
            let folderPath = folder.path(percentEncoded: false)
            let errorDescription = error.localizedDescription
            Logger.wineKit.error(
                "Failed to enforce retention in \(folderPath, privacy: .public): \(errorDescription, privacy: .public)"
            )
        }
    }

    /// Creates a new file handle for logging Wine process output.
    ///
    /// Each call creates a new log file with the current timestamp.
    /// The log directory is created if it doesn't exist.
    ///
    /// - Returns: A `FileHandle` open for writing to the new log file.
    /// - Throws: An error if the log directory or file cannot be created.
    static func makeFileHandle() throws -> FileHandle {
        let (handle, _) = try makeFileHandleWithURL()
        return handle
    }

    /// Creates a new file handle for logging and returns both the handle and the log file URL.
    ///
    /// This variant is used when the caller needs to track the log file location
    /// (e.g., for post-run crash classification).
    ///
    /// - Returns: A tuple of the open `FileHandle` and its log file `URL`.
    /// - Throws: An error if the log directory or file cannot be created.
    static func makeFileHandleWithURL() throws -> (FileHandle, URL) {
        if !FileManager.default.fileExists(atPath: logsFolder.path) {
            try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)
        }

        // Enforce retention before creating a new log file.
        // This is best-effort and only impacts Whisky's own log directory.
        enforceLogRetention(in: logsFolder, maxTotalBytes: maxLogsFolderBytes)

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try (FileHandle(forWritingTo: fileURL), fileURL)
    }

    /// Classifies the output from a Wine process run for crash patterns.
    ///
    /// Reads the head and the tail of the log, not the tail alone: missing-DLL
    /// (`import_dll`) and backend-init failures are head-of-log events, and a
    /// long session buries them under hours of output a tail-only window never
    /// sees. Runs on a background task to avoid blocking the UI.
    ///
    /// - Parameters:
    ///   - logFileURL: URL to the Wine log file to analyze.
    ///   - exitCode: The Wine process exit code.
    ///   - classifier: Optional pre-configured classifier. If `nil`, creates one
    ///     with default patterns.
    /// - Returns: A ``CrashDiagnosis`` if the log was readable, or `nil` on failure.
    public static func classifyLastRun(
        logFileURL: URL,
        exitCode: Int32,
        classifier: CrashClassifier? = nil
    ) async -> CrashDiagnosis? {
        await Task.detached(priority: .utility) {
            guard let logText = try? classificationWindow(of: logFileURL), !logText.isEmpty else {
                return nil
            }
            let resolvedClassifier = classifier ?? CrashClassifier()
            return resolvedClassifier.classify(log: logText, exitCode: exitCode)
        }.value
    }

    /// The head and tail of a log, joined into the window classification reads.
    private nonisolated static func classificationWindow(of logFileURL: URL) throws -> String? {
        let maxTailBytes = 256 * 1_024
        let maxHeadBytes = 64 * 1_024
        let maxTailLines = 500
        let maxHeadLines = 200

        let handle = try FileHandle(forReadingFrom: logFileURL)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()

        if end <= UInt64(maxHeadBytes + maxTailBytes) {
            try handle.seek(toOffset: 0)
            let data = try handle.readToEnd() ?? Data()
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count <= maxHeadLines + maxTailLines {
                return text
            }
            return (lines.prefix(maxHeadLines) + lines.suffix(maxTailLines)).joined(separator: "\n")
        }

        try handle.seek(toOffset: 0)
        let headData = try handle.read(upToCount: maxHeadBytes) ?? Data()
        var head = String(data: headData, encoding: .utf8) ?? ""
        // Drop the trailing partial line of the head window.
        if let lastNewline = head.lastIndex(of: "\n") {
            head = String(head[..<lastNewline])
        }
        let headLines = head
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(maxHeadLines)

        try handle.seek(toOffset: end - UInt64(maxTailBytes))
        let tailData = try handle.readToEnd() ?? Data()
        var tail = String(data: tailData, encoding: .utf8) ?? ""
        // Drop the leading partial line of the tail window.
        if let firstNewline = tail.firstIndex(of: "\n") {
            tail = String(tail[tail.index(after: firstNewline)...])
        }
        let tailLines = tail
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(maxTailLines)

        return (headLines + tailLines).joined(separator: "\n")
    }
}

// swiftlint:enable type_body_length
