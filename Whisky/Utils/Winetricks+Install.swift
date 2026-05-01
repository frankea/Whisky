//
//  Winetricks+Install.swift
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
import os
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WinetricksInstall")

/// Progress events emitted during a headless winetricks verb installation.
enum WinetricksInstallProgress {
    /// The installation is being prepared (environment setup).
    case preparing
    /// A line of output from the winetricks process.
    case output(String)
    /// The installation completed with the given exit code.
    case completed(exitCode: Int32)
    /// The installation failed with an error message.
    case failed(String)
}

// MARK: - Headless Verb Installation

extension Winetricks {
    /// Installs a single winetricks verb headlessly via Process.
    ///
    /// Runs the verb installation as a child process (not via Terminal AppleScript),
    /// streaming stdout and stderr lines as ``WinetricksInstallProgress/output(_:)``
    /// events. This keeps volume access attributed to Whisky rather than Terminal.
    ///
    /// After successful completion, the ``WinetricksVerbCache`` is refreshed
    /// by calling ``loadInstalledVerbs(for:)``.
    ///
    /// - Parameters:
    ///   - verb: The winetricks verb name to install (e.g. "vcrun2019").
    ///   - bottle: The bottle whose prefix to install into.
    ///   - timeout: Maximum time in seconds before the process is terminated.
    ///     Defaults to 600 seconds (10 minutes).
    /// - Returns: An ``AsyncStream`` of progress events.
    static func installVerb(
        _ verb: String,
        for bottle: Bottle,
        timeout: TimeInterval = 600
    ) -> AsyncStream<WinetricksInstallProgress> {
        AsyncStream { continuation in
            Task {
                await executeVerbInstall(verb, for: bottle, timeout: timeout, continuation: continuation)
            }
        }
    }

    /// Installs multiple winetricks verbs sequentially with per-verb progress.
    ///
    /// Verbs are installed one at a time in the order given. A failure in
    /// one verb does not prevent subsequent verbs from being attempted.
    ///
    /// - Parameters:
    ///   - verbs: The winetricks verb names to install.
    ///   - bottle: The bottle whose prefix to install into.
    /// - Returns: An ``AsyncStream`` of tuples pairing the current verb
    ///   name with its progress event.
    static func installVerbs(
        _ verbs: [String],
        for bottle: Bottle
    ) -> AsyncStream<(verb: String, progress: WinetricksInstallProgress)> {
        AsyncStream { continuation in
            Task {
                for verb in verbs {
                    for await progress in installVerb(verb, for: bottle) {
                        continuation.yield((verb: verb, progress: progress))
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Private Helpers

    /// Configures and returns a Process for running a winetricks verb.
    private static func configureInstallProcess(
        verb: String,
        bottleURL: URL,
        resourcesURL: URL
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", winetricksURL.path(percentEncoded: false), verb]
        process.environment = [
            "WINEPREFIX": bottleURL.path(percentEncoded: false),
            "WINE": "wine64",
            "PATH": [
                WhiskyWineInstaller.binFolder.path(percentEncoded: false),
                resourcesURL.path(percentEncoded: false),
                "/usr/bin",
                "/bin"
            ].joined(separator: ":"),
            "HOME": NSHomeDirectory()
        ]
        return process
    }

    /// Attaches readability handlers that forward pipe output as progress events.
    private static func attachOutputHandlers(
        stdout: Pipe,
        stderr: Pipe,
        continuation: AsyncStream<WinetricksInstallProgress>.Continuation
    ) {
        let handler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty
            else { return }
            continuation.yield(.output(line))
        }
        stdout.fileHandleForReading.readabilityHandler = handler
        stderr.fileHandleForReading.readabilityHandler = handler
    }

    /// Executes the verb installation process with timeout and cache refresh.
    private static func executeVerbInstall(
        _ verb: String,
        for bottle: Bottle,
        timeout: TimeInterval,
        continuation: AsyncStream<WinetricksInstallProgress>.Continuation
    ) async {
        continuation.yield(.preparing)

        let bottleURL = await MainActor.run { bottle.url }

        guard let resourcesURL = Bundle.main.url(
            forResource: "cabextract",
            withExtension: nil
        )?.deletingLastPathComponent()
        else {
            logger.warning("Could not locate cabextract resource for winetricks install")
            continuation.yield(.failed("Missing cabextract resource"))
            continuation.finish()
            return
        }

        let process = configureInstallProcess(verb: verb, bottleURL: bottleURL, resourcesURL: resourcesURL)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        attachOutputHandlers(stdout: stdoutPipe, stderr: stderrPipe, continuation: continuation)

        do {
            try process.run()
            logger.info("Started winetricks install for verb '\(verb)'")
        } catch {
            logger.error("Failed to launch winetricks install: \(error.localizedDescription)")
            continuation.yield(.failed(error.localizedDescription))
            continuation.finish()
            return
        }

        await awaitProcessCompletion(process, verb: verb, timeout: timeout)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        logger.info("winetricks install '\(verb)' exited with status \(exitCode)")
        continuation.yield(.completed(exitCode: exitCode))

        // Refresh the verb cache after installation
        _ = await Winetricks.loadInstalledVerbs(for: bottle)
        continuation.finish()
    }

    /// Waits for the process to exit or times out.
    private static func awaitProcessCompletion(
        _ process: Process,
        verb: String,
        timeout: TimeInterval
    ) async {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                logger.warning("winetricks install '\(verb)' timed out after \(Int(timeout)) seconds")
                process.terminate()
            }
        }
        process.waitUntilExit()
        timeoutTask.cancel()
    }
}
