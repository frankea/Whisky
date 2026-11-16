//
//  Wine+ProgramSession.swift
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

/// The App Nap assertion a bottle's `disableAppNap` setting asks for while a
/// program's session runs.
///
/// Whisky reads the session's output and writes it to the log; a napping
/// Whisky reads it late, and Wine processes block on a full pipe.
@MainActor
final class LaunchActivity {
    private var token: NSObjectProtocol?

    init(bottle: Bottle) {
        guard bottle.settings.disableAppNap else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Wine process running for \(bottle.settings.name)"
        )
    }

    /// Ends the assertion. Later calls do nothing.
    func end() {
        if let token {
            ProcessInfo.processInfo.endActivity(token)
        }
        token = nil
    }
}

/// What outlives a program launch: its output, which goes on after the
/// `wine start` launcher exits, until the bottle's session ends.
@MainActor
struct ProgramSession {
    /// Completed once every process holding the launch's output has closed it.
    let pipeCompletion = ProcessOutputCompletion()
    /// Carries what arrives after the launcher exited to `onOutput`, when there is one.
    let lateOutput: AsyncStream<ProcessOutput>.Continuation?
    private let lateDelivery: Task<Void, Never>?

    /// - Parameter onOutput: Receives the output that arrives after the
    ///   launcher exited, in order, on the main actor.
    init(onOutput: (@MainActor (ProcessOutput) -> Void)?) {
        guard let onOutput else {
            lateOutput = nil
            lateDelivery = nil
            return
        }
        let (stream, continuation) = AsyncStream.makeStream(of: ProcessOutput.self)
        lateOutput = continuation
        lateDelivery = Task { @MainActor in
            for await output in stream {
                onOutput(output)
            }
        }
    }

    /// Runs `onClose` once the output has closed and all of it reached
    /// `onOutput`, then completes the returned completion.
    func finish(then onClose: @escaping @MainActor () -> Void) -> ProcessOutputCompletion {
        let completion = ProcessOutputCompletion()
        let pipeCompletion = pipeCompletion
        let lateDelivery = lateDelivery
        Task { @MainActor in
            await pipeCompletion.wait()
            await lateDelivery?.value
            onClose()
            completion.complete()
        }
        return completion
    }
}

extension Wine {
    /// Records a program launch in its run log history, marked running,
    /// removes the logs of the entries the history drops, and posts
    /// ``RecordedLaunch/didRecordNotification`` so a last played date on screen
    /// updates.
    ///
    /// - Returns: The ID of the new entry.
    @MainActor
    static func recordRunStart(
        programName: String, logFileURL: URL, launch: PreparedLaunch,
        programSettings: ProgramSettings?, bottle: Bottle
    ) -> UUID {
        var entry = RunLogEntry(programName: programName, logFileName: logFileURL.lastPathComponent)
        if launch.environment.keys.contains("WINEDEBUG") {
            entry.activeWineDebugPreset = programSettings?.activeWineDebugPreset?.rawValue
        }

        var history = RunLogStore.load(for: programName, in: bottle.url)
        let prunedEntries = history.append(entry)
        RunLogStore.save(history, for: programName, in: bottle.url)

        for pruned in prunedEntries {
            try? FileManager.default.removeItem(at: logsFolder.appending(path: pruned.logFileName))
        }
        RecordedLaunch(bottleURL: bottle.url, target: .program(name: programName), date: entry.startTime).post()
        return entry.id
    }

    /// Marks a run finished in its run log history, once its session's output
    /// has closed, with the exit code of its `wine start` launcher.
    @MainActor
    static func recordRunEnd(id: UUID, programName: String, exitCode: Int32, hasWineDebug: Bool, bottle: Bottle) {
        var history = RunLogStore.load(for: programName, in: bottle.url)
        history.markCompleted(id: id, exitCode: exitCode, hasWineDebug: hasWineDebug)
        RunLogStore.save(history, for: programName, in: bottle.url)
    }
}
