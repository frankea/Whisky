//
//  PreflightCollector.swift
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

/// Gathers cheap, eagerly-collected state at the start of a troubleshooting session.
///
/// The preflight snapshot provides identity and runtime context to
/// ``TroubleshootingCheck`` implementations without requiring expensive
/// diagnostic operations. All data collected here should be fast to obtain
/// (no Wine process launches, no file scanning beyond directory listing).
///
/// Follows the caseless enum pattern used by ``PatternLoader`` and ``GameDBLoader``.
public enum PreflightCollector {
    private static let logger = Logger(
        subsystem: "com.franke.Whisky",
        category: "PreflightCollector"
    )

    /// What the collector reads from the bottle and program on the main actor.
    struct Inputs: Sendable {
        let bottleURL: URL
        let bottleName: String
        let programURL: URL?
        /// The launcher detected for the program, or the one the bottle was
        /// set up for.
        let launcherType: LauncherType?
        let bottleBackend: GraphicsBackend
        /// The program's backend override, when a ``Program`` was at hand.
        let programBackendOverride: GraphicsBackend?
        /// Whether to read the override from the program's settings file:
        /// there is a program URL but no ``Program`` to ask.
        let readsPersistedOverride: Bool
    }

    /// The most recent run of a program found in the run history.
    struct RecentRun: Equatable {
        let logURL: URL?
        let exitCode: Int32?
        var startTime: Date?
    }

    /// Collects cheap preflight data for a troubleshooting session.
    ///
    /// Gathers bottle identity, program identity, the launcher in use,
    /// running process state, the most recent run's log and exit code,
    /// audio device info, and the graphics backend a launch uses (the
    /// program's override first, then the bottle's). Nothing launches Wine;
    /// the file and audio reads run off the main actor.
    ///
    /// - Parameters:
    ///   - bottle: The bottle being troubleshot.
    ///   - program: The program being troubleshot, if any.
    ///   - programURL: The program's URL when there is no ``Program`` for it.
    /// - Returns: A ``PreflightData`` snapshot.
    @MainActor
    public static func collect(bottle: Bottle, program: Program?, programURL: URL? = nil) async -> PreflightData {
        let inputs = inputs(bottle: bottle, program: program, programURL: programURL)
        let gathering = Task.detached(priority: .userInitiated) {
            gather(inputs, logsFolder: Wine.logsFolder)
        }
        // Asynchronous on the main actor: it waits on a process without
        // blocking.
        let isRunning = await Wine.isWineserverRunning(for: bottle)
        let preflight = await gathering.value.with(isWineserverRunning: isRunning)

        logger.debug(
            """
            Preflight: wineserver=\(isRunning), procs=\(preflight.processCount), \
            backend=\(preflight.graphicsBackend), launcher=\(preflight.launcherType ?? "none")
            """
        )
        return preflight
    }

    // MARK: - Steps

    @MainActor
    static func inputs(bottle: Bottle, program: Program?, programURL: URL?) -> Inputs {
        let url = program?.url ?? programURL
        return Inputs(
            bottleURL: bottle.url,
            bottleName: bottle.settings.name,
            programURL: url,
            launcherType: url.flatMap { LauncherType.detect(from: $0) } ?? bottle.settings.detectedLauncher,
            bottleBackend: bottle.settings.graphicsBackend,
            programBackendOverride: program?.settings.overrides?.graphicsBackend,
            readsPersistedOverride: program == nil && url != nil
        )
    }

    /// Everything but the wineserver probe, which the caller fills in.
    static func gather(
        _ inputs: Inputs,
        logsFolder: URL,
        audioDevice: () -> AudioDeviceInfo? = { AudioDeviceMonitor().defaultOutputDevice() },
        recommendedBackend: (LauncherType?) -> GraphicsBackend = { GraphicsBackendResolver.resolve(for: $0) }
    ) -> PreflightData {
        var programOverride = inputs.programBackendOverride
        if inputs.readsPersistedOverride, let programURL = inputs.programURL {
            programOverride = Program.persistedOverrides(for: programURL, bottleURL: inputs.bottleURL)?
                .graphicsBackend
        }
        let backends = resolvedBackends(
            bottle: inputs.bottleBackend,
            programOverride: programOverride,
            programURL: inputs.programURL,
            recommended: recommendedBackend
        )
        let recentRun = recentRun(
            programName: inputs.programURL?.lastPathComponent,
            bottleURL: inputs.bottleURL,
            logsFolder: logsFolder
        )
        let device = audioDevice()

        return PreflightData(
            bottleURL: inputs.bottleURL,
            bottleName: inputs.bottleName,
            programURL: inputs.programURL,
            programName: inputs.programURL?.lastPathComponent,
            launcherType: inputs.launcherType?.rawValue,
            isWineserverRunning: false,
            processCount: ProcessRegistry.shared.getProcessCount(for: inputs.bottleURL),
            recentLogURL: recentRun.logURL,
            lastExitCode: recentRun.exitCode,
            recentRunStartTime: recentRun.startTime,
            audioDeviceName: device?.name,
            audioTransportType: device?.transportType.exportName,
            audioSampleRate: device?.sampleRate,
            graphicsBackend: backends.effective.rawValue,
            bottleGraphicsBackend: backends.bottle.rawValue,
            collectedAt: Date()
        )
    }

    /// The backends a launch of the program and the bottle's other programs
    /// resolve to.
    ///
    /// Mirrors the launch: the program's override wins over the bottle's
    /// setting, and Recommended resolves for what is launched, which steers
    /// a launcher to DXVK.
    static func resolvedBackends(
        bottle: GraphicsBackend,
        programOverride: GraphicsBackend?,
        programURL: URL?,
        recommended: (LauncherType?) -> GraphicsBackend
    ) -> (effective: GraphicsBackend, bottle: GraphicsBackend) {
        let bottleResolved = bottle == .recommended ? recommended(nil) : bottle
        let choice = programOverride ?? bottle
        guard choice == .recommended else {
            return (choice, bottleResolved)
        }
        let launcher = programURL.flatMap { LauncherType.detect(from: $0) }
        return (recommended(launcher), bottleResolved)
    }

    /// The most recent run in the bottle's run history: the program's when
    /// one is named, otherwise the newest of any program in the bottle.
    ///
    /// The log is only returned while its file still exists; run logs live
    /// in the shared logs folder, named in the history entry.
    static func recentRun(programName: String?, bottleURL: URL, logsFolder: URL) -> RecentRun {
        let entries: [RunLogEntry] = if let programName {
            RunLogStore.load(for: programName, in: bottleURL).entries
        } else {
            historyProgramNames(in: bottleURL).flatMap { RunLogStore.load(for: $0, in: bottleURL).entries }
        }
        guard let latest = entries.max(by: { $0.startTime < $1.startTime }) else {
            return RecentRun(logURL: nil, exitCode: nil)
        }
        let logURL = logsFolder.appending(path: latest.logFileName)
        let logExists = FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false))
        return RecentRun(logURL: logExists ? logURL : nil, exitCode: latest.exitCode, startTime: latest.startTime)
    }

    /// The programs with a run history in the bottle.
    private static func historyProgramNames(in bottleURL: URL) -> [String] {
        let suffix = ".run-history.plist"
        let folder = bottleURL.appending(path: "Program Settings")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(suffix) }.map { String($0.dropLast(suffix.count)) }
    }
}

extension PreflightData {
    /// This snapshot with the wineserver state replaced.
    func with(isWineserverRunning: Bool) -> PreflightData {
        PreflightData(
            bottleURL: bottleURL,
            bottleName: bottleName,
            programURL: programURL,
            programName: programName,
            launcherType: launcherType,
            isWineserverRunning: isWineserverRunning,
            processCount: processCount,
            recentLogURL: recentLogURL,
            lastExitCode: lastExitCode,
            recentRunStartTime: recentRunStartTime,
            audioDeviceName: audioDeviceName,
            audioTransportType: audioTransportType,
            audioSampleRate: audioSampleRate,
            graphicsBackend: graphicsBackend,
            bottleGraphicsBackend: bottleGraphicsBackend,
            collectedAt: collectedAt
        )
    }
}
