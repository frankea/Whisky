//
//  ResumableDownloadSupport.swift
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

/// Retry policy for ``ResumableDownloader``: how many attempts to make and how
/// long to back off between them.
public struct ResumableDownloadRetryPolicy: Sendable {
    /// Total attempt budget, counting the first try. `1` disables retries.
    public var maxAttempts: Int

    /// Delay before the first retry. Each subsequent retry doubles it.
    public var initialRetryDelay: TimeInterval

    /// Upper bound on the backoff delay, so a long outage polls at a steady
    /// cadence instead of growing without bound.
    public var maxRetryDelay: TimeInterval

    public init(maxAttempts: Int = 4, initialRetryDelay: TimeInterval = 1, maxRetryDelay: TimeInterval = 15) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialRetryDelay = max(0, initialRetryDelay)
        self.maxRetryDelay = max(self.initialRetryDelay, maxRetryDelay)
    }

    /// The backoff before retry number `retry` (1-based): the initial delay
    /// doubled per retry, capped at ``maxRetryDelay``.
    func delay(beforeRetry retry: Int) -> TimeInterval {
        // Cap the exponent so the shift can't overflow for absurd retry counts.
        let exponent = min(max(retry - 1, 0), 32)
        return min(initialRetryDelay * pow(2, Double(exponent)), maxRetryDelay)
    }
}

/// A snapshot of download progress reported by ``ResumableDownloader``.
public struct ResumableDownloadProgress: Sendable, Equatable {
    /// Bytes persisted to disk so far, including any prefix carried over from
    /// an earlier interrupted attempt.
    public let bytesOnDisk: Int64

    /// Total size of the file when the server advertised one, or `nil`.
    public let expectedBytes: Int64?

    public init(bytesOnDisk: Int64, expectedBytes: Int64?) {
        self.bytesOnDisk = bytesOnDisk
        self.expectedBytes = expectedBytes
    }
}

/// Errors thrown by ``ResumableDownloader/download(from:to:onEvent:progress:)``.
public enum ResumableDownloadError: LocalizedError, Equatable {
    /// The server answered with a status code outside the download protocol
    /// (not 200/206/416). Retried automatically only for transient codes.
    case httpStatus(Int)

    /// The response was not an HTTP response, or the connection closed before
    /// headers arrived.
    case invalidResponse

    /// The connection closed cleanly before all advertised bytes arrived. The
    /// partial file is kept so the next attempt resumes where this one stopped.
    case truncatedTransfer(received: Int64, expected: Int64)

    /// The on-disk partial no longer matches what the server offers (HTTP 416,
    /// or a 206 at an unexpected offset). The partial has been discarded, so
    /// the next attempt starts from a clean slate.
    case staleResume

    public var errorDescription: String? {
        switch self {
        case let .httpStatus(code):
            String(format: String(localized: "setup.whiskywine.error.httpError"), code)
        case .invalidResponse, .truncatedTransfer, .staleResume:
            String(localized: "setup.whiskywine.error.interrupted")
        }
    }
}

/// Sidecar record persisted next to a partial download so a later attempt, or
/// a fresh app launch, can resume it safely.
struct ResumeState: Codable, Equatable {
    /// The absolute source URL. A partial is only ever resumed for the same
    /// URL; a different runtime release downloads to a clean slate.
    var urlString: String

    /// The server's validator for the entity the partial belongs to (a strong
    /// ETag when available, else Last-Modified). Replayed via `If-Range` so a
    /// republished asset produces a full 200 response instead of splicing
    /// bytes from two different files.
    var validator: String?

    /// Total size when the server advertised one.
    var expectedBytes: Int64?

    static func load(from url: URL) -> ResumeState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(ResumeState.self, from: data)
    }

    func save(to url: URL) {
        guard let data = try? PropertyListEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Header parsing for the byte-range resume protocol.
enum HTTPRangeSupport {
    /// Parses a `Content-Range` header of the form `bytes <start>-<end>/<total>`.
    /// Returns the start offset and the total size (`nil` when the server sent
    /// `*` for an unknown total).
    static func parseContentRange(_ value: String?) -> (start: Int64, total: Int64?)? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes") else { return nil }
        let spec = trimmed.dropFirst("bytes".count).trimmingCharacters(in: .whitespaces)
        let parts = spec.split(separator: "/", maxSplits: 1)
        guard let rangePart = parts.first,
              let dash = rangePart.firstIndex(of: "-"),
              let start = Int64(rangePart[..<dash])
        else { return nil }
        let total = parts.count == 2 ? Int64(parts[1]) : nil
        return (start, total)
    }

    /// Picks the validator to record for a response: a strong ETag when the
    /// server sent one, else Last-Modified. Weak ETags (`W/...`) are unusable
    /// for `If-Range` per RFC 9110, so they are skipped.
    static func validator(from response: HTTPURLResponse) -> String? {
        if let etag = response.value(forHTTPHeaderField: "ETag"), !etag.hasPrefix("W/") {
            return etag
        }
        return response.value(forHTTPHeaderField: "Last-Modified")
    }
}

/// Bridges `URLSession`'s data-task delegate callbacks into an async stream so
/// the downloader can inspect response headers and append body chunks to disk
/// as they arrive. A download task only hands over its file at the very end
/// (and deletes it on failure), which is exactly what resumability cannot
/// afford; a data task streamed to an app-owned file keeps every byte.
final class HTTPStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Event {
        case response(URLResponse)
        case chunk(Data)
    }

    /// Response headers first, then body chunks; finishes when the transfer
    /// completes or fails.
    let events: AsyncThrowingStream<Event, Error>
    private let continuation: AsyncThrowingStream<Event, Error>.Continuation

    override init() {
        (events, continuation) = AsyncThrowingStream<Event, Error>.makeStream()
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        continuation.yield(.response(response))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(.chunk(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.finish(throwing: error)
    }
}
