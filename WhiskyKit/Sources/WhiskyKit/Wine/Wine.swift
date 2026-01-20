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
    /// The URL to the `wine64` binary executable.
    ///
    /// This is the main Wine binary used to execute Windows applications.
    /// The binary is located within the WhiskyWine installation directory.
    public static let wineBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wine64")
    /// URL to the `wineserver` binary for Wine server management.
    private static let wineserverBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wineserver")

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

        let wineEnvironment = constructWineEnvironment(for: bottle, environment: environment)

        return try runProcess(
            name: name, args: args, environment: wineEnvironment, executableURL: wineserverBinary,
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
    /// - Throws: An error if the program cannot be started or Wine encounters an error.
    @MainActor
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:]
    ) async throws {
        // Note: Launcher detection is handled at the app level (FileOpenView/BottleView)
        // before calling this method. The detection logic uses LauncherDetection utility
        // which is in the Whisky app target, not WhiskyKit framework.

        // Enable DXVK if needed (either explicitly enabled or auto-enabled for launchers)
        let shouldEnableDXVK = bottle.settings.dxvk ||
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

        for await _ in try runWineProcess(
            name: url.lastPathComponent,
            args: ["start", "/unix", url.path(percentEncoded: false)] + args,
            bottle: bottle, environment: environment
        ) {}
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
        if !FileManager.default.fileExists(atPath: logsFolder.path) {
            try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)
        }

        // Enforce retention before creating a new log file.
        // This is best-effort and only impacts Whisky's own log directory.
        enforceLogRetention(in: logsFolder, maxTotalBytes: maxLogsFolderBytes)

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }
}
