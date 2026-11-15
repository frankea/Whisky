//
//  WineLogFollower.swift
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

/// Where a log's truncation marker is and how many truncations it counts.
public struct WineLogTruncationMarker: Equatable, Sendable {
    /// The marker's offset in the file. Every truncation cuts the log back to
    /// the same head, so the marker stays where it is once written.
    public let offset: UInt64
    /// How many times the log has been truncated, or `nil` when the count
    /// after the marker could not be read.
    public let count: Int?
}

/// Follows a Whisky log as it grows, across the truncations that keep it
/// under its size cap.
///
/// A truncation rewrites everything after the log's head: the marker, then the
/// newest output. The log can grow back past where a reader had got to before
/// the reader looks again, so the file shrinking is not enough to notice one.
/// The follower also compares the truncation count after the marker, and when
/// it changes while the follower is past the head, goes on from the marker. It
/// may then repeat output it already returned, but it never skips any.
public struct WineLogFollower {
    /// Where a new follower starts reading.
    public enum Start: Sendable {
        /// Everything in the log.
        case beginning
        /// Only what is written from now on.
        case end
    }

    /// What one ``read()`` returned.
    public struct Chunk: Sendable {
        /// The bytes written since the last read.
        public let data: Data
        /// Whether the log was truncated since the last read, so `data` starts
        /// again at its truncation marker, or where the marker is about to be written.
        public let resumedAtMarker: Bool
    }

    /// How often a read starts again when the log is rewritten while it reads.
    private static let attempts = 3

    /// The log being followed.
    public let logFileURL: URL
    /// Where the next read starts.
    public private(set) var offset: UInt64 = 0
    /// The marker as of the last read, `nil` while the log held none.
    private var marker: WineLogTruncationMarker?

    /// Starts following the log at `logFileURL`.
    public init(logFileURL: URL, start: Start) {
        self.logFileURL = logFileURL
        guard start == .end, let handle = try? FileHandle(forReadingFrom: logFileURL) else { return }
        defer { try? handle.close() }
        // The marker before the size: a truncation in between makes the next
        // read go on from the marker, which repeats output but skips none.
        marker = Self.marker(in: handle, near: nil)
        offset = (try? handle.seekToEnd()) ?? 0
    }

    /// Reads what was written to the log since the last read.
    ///
    /// - Throws: An error when the log can't be opened or read.
    public mutating func read() throws -> Chunk {
        try read(betweenChecks: {})
    }

    /// ``read()``, running `betweenChecks` after the data is read and before the
    /// marker is looked at again. Tests rewrite the log there.
    mutating func read(betweenChecks: () -> Void) throws -> Chunk {
        let handle = try FileHandle(forReadingFrom: logFileURL)
        defer { try? handle.close() }

        for _ in 0 ..< Self.attempts {
            let before = Self.marker(in: handle, near: marker?.offset)
            let size = try handle.seekToEnd()
            let resumes = isRewritten(size: size, current: before)
            let start = resumes ? min(before?.offset ?? size, size) : offset
            try handle.seek(toOffset: start)
            let data = try handle.readToEnd() ?? Data()
            betweenChecks()
            // A truncation while reading changes the marker, since the marker is
            // written before any output that follows it: read again.
            guard Self.marker(in: handle, near: before?.offset ?? marker?.offset) == before else { continue }
            offset = start + UInt64(data.count)
            marker = before
            return Chunk(data: data, resumedAtMarker: resumes)
        }
        // Rewritten on every attempt; the next read tries again from the same place.
        return Chunk(data: Data(), resumedAtMarker: false)
    }

    /// Whether the log was rewritten past the head since the last read.
    private func isRewritten(size: UInt64, current: WineLogTruncationMarker?) -> Bool {
        if size < offset { return true }
        guard let current, current != marker else { return false }
        // A follower still in the head reads on into the marker: a truncation
        // keeps the head as it was.
        return offset > current.offset
    }

    /// The truncation marker in the log `handle` reads, or `nil` when it holds none.
    ///
    /// - Parameter knownOffset: Where the marker was last seen, checked first.
    static func marker(in handle: FileHandle, near knownOffset: UInt64?) -> WineLogTruncationMarker? {
        let markerData = Data(Wine.logTruncationMarker.utf8)
        // The marker, its count line, and room for any count.
        let markerLength = markerData.count + Wine.logTruncationCountPrefix.utf8.count + 24
        if let knownOffset,
           (try? handle.seek(toOffset: knownOffset)) != nil,
           let data = try? handle.read(upToCount: markerLength),
           data.starts(with: markerData) {
            return WineLogTruncationMarker(offset: knownOffset, count: count(after: markerData.count, in: data))
        }
        // The marker directly follows the head, which is never longer than this.
        guard (try? handle.seek(toOffset: 0)) != nil,
              let data = try? handle.read(upToCount: Wine.logHeadBytes + markerLength),
              let range = data.range(of: markerData)
        else { return nil }
        let offset = data.distance(from: data.startIndex, to: range.lowerBound)
        let afterMarker = Data(data[range.lowerBound...])
        return WineLogTruncationMarker(
            offset: UInt64(offset),
            count: count(after: markerData.count, in: afterMarker)
        )
    }

    /// The truncation count on the line that starts `markerLength` bytes into `data`.
    private static func count(after markerLength: Int, in data: Data) -> Int? {
        let rest = data.dropFirst(markerLength)
        // Only a whole line: a count still being written could read as a smaller one.
        guard let newline = rest.firstIndex(of: UInt8(ascii: "\n")),
              let text = String(data: Data(rest[..<newline]), encoding: .utf8),
              text.hasPrefix(Wine.logTruncationCountPrefix)
        else { return nil }
        return Int(text.dropFirst(Wine.logTruncationCountPrefix.count))
    }
}

public extension Wine {
    /// Where a log's truncation marker is and how many truncations it counts.
    ///
    /// - Parameter logFileURL: The log to look in.
    /// - Returns: The marker, or `nil` when the log holds none or can't be read.
    static func truncationMarker(inLogAt logFileURL: URL) -> WineLogTruncationMarker? {
        guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return nil }
        defer { try? handle.close() }
        return WineLogFollower.marker(in: handle, near: nil)
    }
}
