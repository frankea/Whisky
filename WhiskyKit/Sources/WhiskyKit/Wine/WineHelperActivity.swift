//
//  WineHelperActivity.swift
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

/// The Wine processes Whisky runs in a bottle for its own purposes.
///
/// Creating a bottle, reading or writing its registry and listing its
/// processes all run Wine in the bottle, which brings up its wineserver for as
/// long as they run and a few seconds after. That wineserver is Whisky's doing
/// but no launch's, so ``BottleRunState`` must neither call it orphaned nor
/// count it as a running program. This tracks the helpers that are running,
/// and when the bottle was last seen with nothing but them and Wine's own
/// processes.
public final class WineHelperActivity: @unchecked Sendable {
    public static let shared = WineHelperActivity()

    /// How long a wineserver may stay up once its last helper has finished.
    ///
    /// Wine gives the bottle's system processes about 2 seconds to shut down
    /// and keeps the wineserver 3 seconds after that; the rest is margin.
    public static let settleTime: TimeInterval = 15

    private let lock = NSLock()
    private var runningHelpers: [URL: Int] = [:]
    private var quietSince: [URL: Date] = [:]

    init() {}

    /// Records that a helper started in the bottle. Pair it with ``end(bottleURL:at:)``.
    ///
    /// - Parameter bottleURL: The bottle the helper runs in.
    public func begin(bottleURL: URL) {
        lock.lock()
        runningHelpers[bottleURL, default: 0] += 1
        lock.unlock()
    }

    /// Records that a helper in the bottle has finished.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle the helper ran in.
    ///   - date: When it finished.
    public func end(bottleURL: URL, at date: Date = Date()) {
        lock.lock()
        let remaining = (runningHelpers[bottleURL] ?? 0) - 1
        runningHelpers[bottleURL] = remaining > 0 ? remaining : nil
        quietSince[bottleURL] = date
        lock.unlock()
    }

    /// Records that the bottle was seen running nothing but Wine's own processes.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle that was listed.
    ///   - date: When it was listed.
    public func noteNothingRunning(bottleURL: URL, at date: Date = Date()) {
        lock.lock()
        quietSince[bottleURL] = date
        lock.unlock()
    }

    /// Whether Whisky's own helpers account for the bottle's wineserver being up.
    ///
    /// - Parameters:
    ///   - bottleURL: The bottle to ask about.
    ///   - now: The time of the question.
    /// - Returns: `true` while a helper runs there, and for ``settleTime`` after
    ///   the last one finished or the bottle was last seen running nothing.
    public func accountsForWineserver(bottleURL: URL, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if runningHelpers[bottleURL] != nil {
            return true
        }
        guard let quietSince = quietSince[bottleURL] else { return false }
        return now.timeIntervalSince(quietSince) < Self.settleTime
    }

    /// Weighs a listing of the bottle's processes against its launch session.
    ///
    /// The listing helper keeps the wineserver up while it polls, so after a
    /// game exits the wineserver alone would keep its session running. A
    /// listing that shows Wine's own processes and nothing else, once no launch
    /// is still starting, says the session is over: it is ended, and the
    /// wineserver the listing keeps up is accounted for.
    ///
    /// - Parameters:
    ///   - processes: The processes the listing found.
    ///   - bottleURL: The bottle that was listed.
    ///   - registry: The registry holding the bottle's session.
    ///   - now: When the listing ran.
    /// - Returns: `true` when the listing showed nothing running.
    @discardableResult
    public func recordListing(
        _ processes: [WineProcess], bottleURL: URL, registry: ProcessRegistry = .shared, now: Date = Date()
    ) -> Bool {
        // No rows means the listing itself failed, not that nothing runs:
        // with a wineserver up, Wine's own processes are always listed.
        guard !processes.isEmpty, !processes.contains(where: Self.isProgram) else { return false }
        if let lastLaunch = registry.lastLaunch(for: bottleURL),
           now.timeIntervalSince(lastLaunch) < BottleRunState.startupGrace {
            return false
        }
        // Before ending the session, so a probe it triggers sees the wineserver accounted for.
        noteNothingRunning(bottleURL: bottleURL, at: now)
        registry.endSession(for: bottleURL)
        return true
    }

    /// Whether a listed process is a program rather than Wine's own or the listing's.
    static func isProgram(_ process: WineProcess) -> Bool {
        process.kind == .app && process.imageName.lowercased() != "tasklist.exe"
    }

    /// Forgets all activity. For testing purposes only.
    func reset() {
        lock.lock()
        runningHelpers.removeAll()
        quietSince.removeAll()
        lock.unlock()
    }
}
