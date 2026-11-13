//
//  Wine+ProcessManagement.swift
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

private let processLogger = Logger(
    subsystem: Bundle.whiskyBundleIdentifier,
    category: "Wine.ProcessManagement"
)

// MARK: - Wine Process Management Helpers

public extension Wine {
    /// Probes whether a wineserver is currently running for the given bottle.
    ///
    /// Uses `wineserver -k0` which sends signal 0 (a no-op) to the wineserver.
    /// Exit code 0 means the wineserver is alive; any other code (or error)
    /// means it is not running. This does **not** spawn a new wineserver.
    ///
    /// - Parameter bottle: The bottle whose wineserver to probe.
    /// - Returns: `true` if the wineserver is active, `false` otherwise.
    @MainActor
    static func isWineserverRunning(for bottle: Bottle) async -> Bool {
        // Deliberately does NOT go through runWineserverProcess: a -k0 probe
        // only needs WINEPREFIX, while the full path builds the entire launch
        // environment and creates + retention-scans a log file per call — the
        // sidebar repeats this probe every 60 seconds for every visible bottle.
        let running: Bool = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = WhiskyWineInstaller.binFolder.appending(path: "wineserver")
            process.arguments = ["-k0"]
            process.environment = ["WINEPREFIX": bottle.url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { probe in
                continuation.resume(returning: probe.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }

        processLogger.debug(
            "Wineserver probe for '\(bottle.settings.name)': \(running ? "active" : "idle")"
        )
        return running
    }

    /// Lists the bottle's Wine processes as `tasklist.exe` reports them.
    ///
    /// `tasklist.exe` is a Wine process in the bottle, so unlike the `-k0` probe
    /// above it runs with the bottle's full environment, the way any other helper
    /// does. What it skips is the log file. The Processes page polls this every
    /// few seconds, as does the Steam client driver while it watches Steam, and a
    /// log per call buried the launch logs people are asked to attach.
    ///
    /// - Parameter bottle: The bottle whose processes to list.
    /// - Returns: The parsed process list.
    /// - Throws: An error if `tasklist.exe` cannot be started.
    @MainActor
    static func listProcesses(for bottle: Bottle) async throws -> [WineProcess] {
        let output = try await runWineWithBottle(
            ["tasklist.exe", "/FO", "CSV"], bottle: bottle, createsLogFile: false
        )
        return parseTasklistOutput(output)
    }

    /// Parses the CSV output of `tasklist.exe` into an array of ``WineProcess`` values.
    ///
    /// The expected format is quoted CSV with a header line:
    /// ```
    /// "Image Name","PID","Session Name","Session#","Mem Usage"
    /// "game.exe","42","Console","0","24 K"
    /// ```
    ///
    /// Lines that cannot be parsed (wrong field count, non-numeric PID) are silently skipped.
    /// All returned processes have ``ProcessSource/untracked`` source; the caller should
    /// update the source after merging with ``ProcessRegistry`` data.
    ///
    /// - Parameter output: The raw string output from `tasklist.exe`.
    /// - Returns: An array of parsed ``WineProcess`` instances.
    static func parseTasklistOutput(_ output: String) -> [WineProcess] {
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        var processes: [WineProcess] = []
        processes.reserveCapacity(lines.count)

        for line in lines {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { field in
                    var trimmed = field.trimmingCharacters(in: .whitespaces)
                    // Strip surrounding quotes
                    if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
                        trimmed = String(trimmed.dropFirst().dropLast())
                    }
                    return trimmed
                }

            // Require at least 5 fields: Image Name, PID, Session Name, Session#, Mem Usage
            guard fields.count >= 5 else { continue }

            // Skip the header line
            if fields[1] == "PID" { continue }

            // Parse the PID
            guard let pid = Int32(fields[1]) else { continue }

            let imageName = fields[0]
            let memoryUsage = fields[4]

            processes.append(WineProcess(
                imageName: imageName,
                winePID: pid,
                memoryUsage: memoryUsage,
                kind: ProcessKind.classify(imageName)
            ))
        }

        return processes
    }

    /// Sends a graceful kill request for a single Wine process via `taskkill.exe`.
    ///
    /// This asks the process to terminate cleanly. If the process has already
    /// exited, the error is silently ignored.
    ///
    /// - Parameters:
    ///   - winePID: The Wine/Windows PID to terminate.
    ///   - bottle: The bottle containing the process.
    @MainActor
    static func gracefulKillProcess(winePID: Int32, bottle: Bottle) async {
        do {
            try await Wine.runWine(
                ["taskkill.exe", "/PID", String(winePID)],
                bottle: bottle
            )
            processLogger.info("Sent graceful kill to Wine PID \(winePID)")
        } catch {
            processLogger.debug(
                "Graceful kill for Wine PID \(winePID) failed (process may have exited): \(error.localizedDescription)"
            )
        }
    }

    /// Sends a forced kill request for a single Wine process via `taskkill.exe /F`.
    ///
    /// This forcefully terminates the process without giving it a chance to
    /// clean up. If the process has already exited, the error is silently ignored.
    ///
    /// - Parameters:
    ///   - winePID: The Wine/Windows PID to terminate.
    ///   - bottle: The bottle containing the process.
    @MainActor
    static func forceKillProcess(winePID: Int32, bottle: Bottle) async {
        do {
            try await Wine.runWine(
                ["taskkill.exe", "/PID", String(winePID), "/F"],
                bottle: bottle
            )
            processLogger.info("Sent force kill to Wine PID \(winePID)")
        } catch {
            processLogger.debug(
                "Force kill for Wine PID \(winePID) failed (process may have exited): \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Launch Tracking

public extension Wine {
    /// Whether the bottle has something running, and whether Whisky started it.
    ///
    /// Probes the bottle's wineserver and weighs it against the launches the
    /// ``ProcessRegistry`` knows about
    /// (``BottleRunState/resolve(trackedCount:lastLaunch:wineserverRunning:now:grace:)``).
    /// A session whose wineserver has gone idle is ended here, so its tracked
    /// launches stop counting.
    ///
    /// - Parameter bottle: The bottle to probe.
    /// - Returns: The bottle's state.
    @MainActor
    static func runState(for bottle: Bottle) async -> BottleRunState {
        let wineserverRunning = await isWineserverRunning(for: bottle)
        // Read after the probe, so a launch registered while it ran counts.
        let registry = ProcessRegistry.shared
        let state = BottleRunState.resolve(
            trackedCount: registry.getProcessCount(for: bottle.url),
            lastLaunch: registry.lastLaunch(for: bottle.url),
            wineserverRunning: wineserverRunning
        )
        if state == .idle {
            registry.endSession(for: bottle.url)
        }
        return state
    }
}

extension Wine {
    /// Bottles with a ``watchSession(for:)`` loop running.
    @MainActor private static var watchedSessions: Set<URL> = []

    /// Records a launch the user asked for that has no program entry of its
    /// own, such as a batch file or `winecfg`, and watches for its session to end.
    @MainActor
    static func noteUserLaunch(in bottle: Bottle) {
        ProcessRegistry.shared.noteLaunch(bottleURL: bottle.url)
        watchSession(for: bottle)
    }

    /// Starts a program's `wine64` process, tracked in the ``ProcessRegistry``.
    ///
    /// The process is registered before it starts and given its PID once it
    /// has one, and the bottle's session is watched until its wineserver goes idle.
    @MainActor
    static func startTrackedProgram(
        _ process: Process, name: String, bottle: Bottle, fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let registry = ProcessRegistry.shared
        registry.register(process: process, bottle: bottle, programName: name)
        let stream: AsyncStream<ProcessOutput>
        do {
            stream = try process.runStream(name: name, fileHandle: fileHandle)
        } catch {
            registry.unregister(process: process)
            throw error
        }
        registry.updatePID(pid: process.processIdentifier, for: process)
        watchSession(for: bottle)
        return stream
    }

    /// Updates a program's entry once its `wine start` process has exited.
    ///
    /// The program itself runs on under the wineserver, so a clean exit keeps
    /// the entry but drops the PID: it belongs to a process that is gone and
    /// may be reused, and a stop must never signal it. A failed start leaves
    /// nothing running, so its entry goes.
    @MainActor
    static func launcherDidExit(_ process: Process, exitCode: Int32) {
        if exitCode == 0 {
            ProcessRegistry.shared.updatePID(pid: 0, for: process)
        } else {
            ProcessRegistry.shared.unregister(process: process)
        }
    }

    /// Ends the bottle's session once its wineserver goes idle.
    ///
    /// Something has to look: the sidebar only probes the bottles it shows, and
    /// a session left open would keep its launches counted, and the display
    /// awake, after the game is gone. One loop per bottle; a launch while it
    /// runs only moves the session's start.
    @MainActor
    static func watchSession(for bottle: Bottle, interval: Duration = .seconds(30)) {
        guard watchedSessions.insert(bottle.url).inserted else { return }
        Task { @MainActor in
            defer { watchedSessions.remove(bottle.url) }
            repeat {
                try? await Task.sleep(for: interval)
            } while await runState(for: bottle).isRunning
        }
    }
}
