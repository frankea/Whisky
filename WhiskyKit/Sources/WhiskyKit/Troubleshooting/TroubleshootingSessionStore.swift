//
//  TroubleshootingSessionStore.swift
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

// MARK: - Staleness Change

/// Describes a single change detected between a session's preflight snapshot
/// and the current system state, used to drive the "Since you left" resume banner.
public struct StalenessChange: Sendable {
    /// The name of the field that changed.
    public let field: String

    /// The previous value from the session snapshot.
    public let oldValue: String

    /// The current value from fresh preflight data.
    public let newValue: String

    /// A user-facing message describing the change.
    public let displayMessage: String

    public init(field: String, oldValue: String, newValue: String, displayMessage: String) {
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.displayMessage = displayMessage
    }
}

// MARK: - Session Store

/// Concrete implementation of ``TroubleshootingSessionStoring`` that persists
/// active sessions to plist files per bottle and manages bounded history.
///
/// Active sessions are stored as `TroubleshootingSession.plist` in the bottle
/// directory. Stale sessions (older than 14 days) are expired on load. Completed
/// sessions are archived into ``TroubleshootingHistory`` with bounded retention.
///
/// All file writes use `.atomic` to prevent corruption on crash.
public struct TroubleshootingSessionStore: TroubleshootingSessionStoring {
    /// The plist filename for active sessions within a bottle directory.
    public static let activeSessionFileName = "TroubleshootingSession.plist"

    /// Number of days after which an unfinished session is considered stale.
    public static let staleSessionDays = 14

    private let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "TroubleshootingSessionStore"
    )

    /// Creates a new session store.
    public init() {}

    // MARK: - TroubleshootingSessionStoring

    /// Saves the current session state to the bottle directory.
    ///
    /// Updates `lastUpdatedAt` before encoding. Uses `.atomic` writes
    /// to prevent corruption on crash or power loss.
    ///
    /// - Parameter session: The session to persist.
    public func save(_ session: TroubleshootingSession) {
        guard let bottleURL = session.bottleURL else {
            logger.warning("Cannot save session: no bottleURL")
            return
        }

        var mutableSession = session
        mutableSession.lastUpdatedAt = Date()

        let url = bottleURL.appendingPathComponent(Self.activeSessionFileName)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(mutableSession)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save active session: \(error.localizedDescription)")
        }
    }

    /// Marks a session as complete, archives it to history, and deletes the active file.
    ///
    /// Creates a ``TroubleshootingHistoryEntry`` from the session summary fields,
    /// appends it to the bottle's ``TroubleshootingHistory``, and removes the
    /// active session plist.
    ///
    /// - Parameter session: The completed session.
    public func completeSession(_ session: TroubleshootingSession) {
        guard let bottleURL = session.bottleURL else {
            logger.warning("Cannot complete session: no bottleURL")
            return
        }

        // Extract summary fields for the history entry
        let entry = TroubleshootingHistoryEntry(
            symptomCategory: session.symptomCategory ?? .other,
            outcome: session.outcome ?? .abandoned,
            primaryFindings: session.checkResults.values.map(\.summary),
            fixesAttempted: session.fixAttempts.map(\.fixId),
            fixResults: session.fixAttempts.map { attempt in
                "\(attempt.fixId): \(attempt.result.rawValue)"
            },
            startedAt: session.createdAt,
            completedAt: Date(),
            programName: session.preflightSnapshot?.programName,
            bottleName: session.preflightSnapshot?.bottleName ?? "Unknown"
        )

        // Append to history and save
        var history = TroubleshootingHistory.load(from: bottleURL)
        history.append(entry)
        history.save(to: bottleURL)

        // Delete the active session file
        deleteActiveSession(for: bottleURL)
    }

    // MARK: - Active Session Management

    /// Loads the active session for a bottle, returning `nil` if none exists or it is stale.
    ///
    /// If the session's `lastUpdatedAt` is more than ``staleSessionDays`` old,
    /// the file is deleted and `nil` is returned so the user starts fresh.
    ///
    /// - Parameter bottleURL: The URL of the bottle directory.
    /// - Returns: The active session, or `nil` if none exists or it expired.
    public func loadActiveSession(for bottleURL: URL) -> TroubleshootingSession? {
        let url = bottleURL.appendingPathComponent(Self.activeSessionFileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let session = try PropertyListDecoder().decode(TroubleshootingSession.self, from: data)

            // Check staleness: if lastUpdatedAt is more than 14 days ago, expire
            let cutoff = Calendar.current.date(
                byAdding: .day,
                value: -Self.staleSessionDays,
                to: Date()
            ) ?? Date()

            if session.lastUpdatedAt < cutoff {
                logger.info("Active session is stale (last updated \(session.lastUpdatedAt)), deleting")
                deleteActiveSession(for: bottleURL)
                return nil
            }

            return session
        } catch {
            logger.error("Failed to decode active session: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes the active session plist file for a bottle.
    ///
    /// - Parameter bottleURL: The URL of the bottle directory.
    public func deleteActiveSession(for bottleURL: URL) {
        let url = bottleURL.appendingPathComponent(Self.activeSessionFileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// Checks whether an active, non-stale session exists for a bottle.
    ///
    /// - Parameter bottleURL: The URL of the bottle directory.
    /// - Returns: `true` if a valid active session file exists.
    public func hasActiveSession(for bottleURL: URL) -> Bool {
        loadActiveSession(for: bottleURL) != nil
    }

    // MARK: - Staleness Detection

    /// Compares a session's preflight snapshot against current preflight data
    /// to detect changes that occurred while the session was paused.
    ///
    /// Used to drive the "Since you left" banner on session resume.
    ///
    /// - Parameters:
    ///   - session: The paused session with a stored preflight snapshot.
    ///   - currentPreflight: Fresh preflight data collected now.
    /// - Returns: An array of detected changes, empty if nothing changed.
    public func checkStaleness(
        session: TroubleshootingSession,
        currentPreflight: PreflightData
    ) -> [StalenessChange] {
        guard let snapshot = session.preflightSnapshot else {
            return []
        }

        var changes: [StalenessChange] = []

        // Graphics backend changed
        if snapshot.graphicsBackend != currentPreflight.graphicsBackend {
            changes.append(StalenessChange(
                field: "graphicsBackend",
                oldValue: snapshot.graphicsBackend,
                newValue: currentPreflight.graphicsBackend,
                displayMessage: "Graphics backend changed from \(snapshot.graphicsBackend) "
                    + "to \(currentPreflight.graphicsBackend)"
            ))
        }

        // Audio device name changed
        let oldAudio = snapshot.audioDeviceName ?? "none"
        let newAudio = currentPreflight.audioDeviceName ?? "none"
        if oldAudio != newAudio {
            changes.append(StalenessChange(
                field: "audioDeviceName",
                oldValue: oldAudio,
                newValue: newAudio,
                displayMessage: "Audio output device changed from \(oldAudio) to \(newAudio)"
            ))
        }

        // Wineserver running state changed
        if snapshot.isWineserverRunning != currentPreflight.isWineserverRunning {
            let oldState = snapshot.isWineserverRunning ? "running" : "stopped"
            let newState = currentPreflight.isWineserverRunning ? "running" : "stopped"
            changes.append(StalenessChange(
                field: "isWineserverRunning",
                oldValue: oldState,
                newValue: newState,
                displayMessage: "Wine server is now \(newState) (was \(oldState))"
            ))
        }

        // Process count significantly different (>50% change or delta > 5)
        let oldCount = snapshot.processCount
        let newCount = currentPreflight.processCount
        let delta = abs(oldCount - newCount)
        let threshold = max(oldCount / 2, 5)
        if delta >= threshold, oldCount != newCount {
            changes.append(StalenessChange(
                field: "processCount",
                oldValue: String(oldCount),
                newValue: String(newCount),
                displayMessage: "Wine process count changed from \(oldCount) to \(newCount)"
            ))
        }

        return changes
    }
}
