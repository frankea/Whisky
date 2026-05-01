//
//  AudioDeviceHistory.swift
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

/// Bounded ring buffer of audio device change events.
///
/// Maintains the last ``maxEvents`` events with FIFO eviction and 30-second
/// deduplication. Matches the ``DiagnosisHistory`` pattern from Phase 5.
///
/// Not isolated to any actor -- this is a pure data container.
public final class AudioDeviceHistory: Codable, @unchecked Sendable {
    /// Maximum number of events retained.
    public let maxEvents: Int

    /// The stored change events, ordered oldest-first.
    public private(set) var events: [AudioDeviceChangeEvent]

    /// Duration within which duplicate events (same device name and event type)
    /// are coalesced rather than appended.
    private static let deduplicationWindow: TimeInterval = 30

    /// Creates an empty device history with the specified capacity.
    ///
    /// - Parameter maxEvents: The maximum number of events to retain. Defaults to 20.
    public init(maxEvents: Int = 20) {
        self.maxEvents = maxEvents
        self.events = []
    }

    /// Appends a new event, applying deduplication and FIFO eviction.
    ///
    /// If an existing event with the same device name and event type occurred
    /// within the last 30 seconds, the new event is silently dropped.
    ///
    /// - Parameter event: The change event to record.
    public func append(_ event: AudioDeviceChangeEvent) {
        let dominated = events.contains { existing in
            existing.deviceName == event.deviceName
                && existing.eventType == event.eventType
                && event.timestamp.timeIntervalSince(existing.timestamp) < Self.deduplicationWindow
        }

        guard !dominated else { return }

        events.append(event)
        while events.count > maxEvents {
            events.removeFirst()
        }
    }

    /// Removes all events from the history.
    public func clear() {
        events.removeAll()
    }

    /// Returns a copy of the current events for export or display.
    public func export() -> [AudioDeviceChangeEvent] {
        events
    }
}
