//
//  ResumableDownloader.swift
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
import os

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ResumableDownloader")

/// Downloads a file over HTTP with resume support and bounded automatic retry.
///
/// Interrupted transfers keep their partial bytes on disk (next to the final
/// destination, with a sidecar resume record), so the next attempt, whether an
/// automatic retry, a user-initiated one, or a fresh app launch, continues from
/// where the last one stopped instead of restarting from byte zero. Resumes use
/// HTTP `Range` requests guarded by `If-Range`, so a republished asset falls
/// back to a clean full download rather than splicing bytes from two different
/// files.
///
/// This is transport-level recovery only: callers remain responsible for
/// content integrity (the runtime install path verifies the advertised SHA-256
/// before extracting, and discards the file via ``discardArtifacts(at:)`` on a
/// mismatch).
public final class ResumableDownloader: @unchecked Sendable {
    // Both stored properties are set at init and never mutated afterwards
    // (the session configuration is treated as frozen), hence @unchecked.
    private let sessionConfiguration: URLSessionConfiguration
    private let retryPolicy: ResumableDownloadRetryPolicy

    /// - Parameters:
    ///   - sessionConfiguration: Configuration for the URLSession each attempt
    ///     runs on. Must not be mutated after being handed over.
    ///   - retryPolicy: Attempt budget and backoff for transient failures.
    public init(
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        retryPolicy: ResumableDownloadRetryPolicy = ResumableDownloadRetryPolicy()
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.retryPolicy = retryPolicy
    }

    // MARK: - On-disk layout

    /// Where in-flight bytes accumulate for `destination`.
    static func partialURL(for destination: URL) -> URL {
        destination.appendingPathExtension("partial")
    }

    /// Where the resume record for `destination` lives.
    static func resumeStateURL(for destination: URL) -> URL {
        destination.appendingPathExtension("resume")
    }

    /// Removes the downloaded file plus any partial data and resume state for
    /// `destination`. Call after a failed integrity check so the next download
    /// starts from a clean slate.
    public static func discardArtifacts(at destination: URL) {
        for url in [destination, partialURL(for: destination), resumeStateURL(for: destination)] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Removes only the in-flight artifacts (partial bytes and resume record).
    private static func discardPartial(for destination: URL) {
        try? FileManager.default.removeItem(at: partialURL(for: destination))
        try? FileManager.default.removeItem(at: resumeStateURL(for: destination))
    }

    // MARK: - Download

    /// Downloads `url` to `destination`, resuming any compatible partial left
    /// by an earlier attempt and retrying transient failures with exponential
    /// backoff. On success the completed file sits at `destination` and all
    /// in-flight artifacts are gone. On failure the partial bytes stay behind
    /// for the next call to resume. Throws `CancellationError` when the
    /// surrounding task is cancelled.
    ///
    /// - Parameters:
    ///   - url: The source URL.
    ///   - destination: The final location for the completed file.
    ///   - onEvent: Diagnostic callback for notable transport events (resume
    ///     offsets, retries). Messages are developer-facing, not localized.
    ///   - progress: Called as bytes reach disk.
    public func download(
        from url: URL,
        to destination: URL,
        onEvent: @escaping @Sendable (String) -> Void = { _ in },
        progress: @escaping @Sendable (ResumableDownloadProgress) -> Void = { _ in }
    ) async throws {
        var attempt = 1
        while true {
            do {
                try await performAttempt(url: url, destination: destination, onEvent: onEvent, progress: progress)
                return
            } catch {
                // A cancelled URLSession task surfaces as URLError.cancelled;
                // report it as task cancellation, never as a download failure.
                try Task.checkCancellation()
                guard Self.isTransient(error), attempt < retryPolicy.maxAttempts else {
                    throw error
                }
                let delay = retryPolicy.delay(beforeRetry: attempt)
                let message = "Attempt \(attempt) of \(retryPolicy.maxAttempts) failed"
                    + " (\(error.localizedDescription)); retrying in \(String(format: "%.1f", delay))s"
                logger.warning("\(message)")
                onEvent(message)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }

    /// Whether `error` is worth retrying without user involvement: dropped or
    /// unreachable connections, stalls, transient HTTP statuses, and resume
    /// state the server rejected (the retry then starts clean).
    static func isTransient(_ error: Error) -> Bool {
        switch error {
        case let downloadError as ResumableDownloadError:
            switch downloadError {
            case let .httpStatus(code):
                code == 408 || code == 429 || (500 ... 599).contains(code)
            case .truncatedTransfer, .staleResume:
                true
            case .invalidResponse:
                false
            }
        case let urlError as URLError:
            Self.transientURLErrorCodes.contains(urlError.code)
        default:
            false
        }
    }

    private static let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
        .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable,
        .secureConnectionFailed, .dataNotAllowed
    ]

    // MARK: - Single attempt

    /// Inputs threaded through one attempt.
    private struct AttemptContext {
        let url: URL
        let destination: URL
        let partialURL: URL
        let stateURL: URL
        let resumeOffset: Int64
        let onEvent: @Sendable (String) -> Void
        let progress: @Sendable (ResumableDownloadProgress) -> Void
    }

    private func performAttempt(
        url: URL,
        destination: URL,
        onEvent: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (ResumableDownloadProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let partialURL = Self.partialURL(for: destination)
        let stateURL = Self.resumeStateURL(for: destination)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // Resume only when the recorded state matches this URL and partial
        // bytes actually exist; otherwise clear leftovers and start clean.
        var resumeOffset: Int64 = 0
        var validator: String?
        if let state = ResumeState.load(from: stateURL),
           state.urlString == url.absoluteString,
           let partialSize = Self.fileSize(at: partialURL),
           partialSize > 0 {
            resumeOffset = partialSize
            validator = state.validator
        } else {
            Self.discardPartial(for: destination)
        }

        var request = URLRequest(url: url)
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
            if let validator {
                request.setValue(validator, forHTTPHeaderField: "If-Range")
            }
            onEvent("Resuming download from byte \(resumeOffset)")
        }

        let context = AttemptContext(
            url: url,
            destination: destination,
            partialURL: partialURL,
            stateURL: stateURL,
            resumeOffset: resumeOffset,
            onEvent: onEvent,
            progress: progress
        )

        let delegate = HTTPStreamDelegate()
        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)

        try await withTaskCancellationHandler {
            try await consume(events: delegate.events, task: task, context: context)
        } onCancel: {
            task.cancel()
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func consume(
        events: AsyncThrowingStream<HTTPStreamDelegate.Event, Error>,
        task: URLSessionDataTask,
        context: AttemptContext
    ) async throws {
        task.resume()
        let fileManager = FileManager.default
        var handle: FileHandle?
        var bytesOnDisk = context.resumeOffset
        var expectedTotal: Int64?
        var sawResponse = false
        defer { try? handle?.close() }

        for try await event in events {
            switch event {
            case let .response(response):
                sawResponse = true
                guard let http = response as? HTTPURLResponse else {
                    task.cancel()
                    throw ResumableDownloadError.invalidResponse
                }
                switch Self.disposition(for: http, resumeOffset: context.resumeOffset) {
                case let .append(total):
                    expectedTotal = total
                    let fileHandle = try FileHandle(forWritingTo: context.partialURL)
                    try fileHandle.seekToEnd()
                    handle = fileHandle
                case let .restart(total):
                    expectedTotal = total
                    bytesOnDisk = 0
                    fileManager.createFile(atPath: context.partialURL.path(percentEncoded: false), contents: nil)
                    handle = try FileHandle(forWritingTo: context.partialURL)
                    if context.resumeOffset > 0 {
                        context.onEvent("Server restarted the download from the beginning")
                    }
                case .stale:
                    task.cancel()
                    Self.discardPartial(for: context.destination)
                    throw ResumableDownloadError.staleResume
                case let .failure(code):
                    task.cancel()
                    throw ResumableDownloadError.httpStatus(code)
                }
                // Record resume state as soon as headers arrive, so a partial
                // left by a crash or quit is resumable on the next launch.
                ResumeState(
                    urlString: context.url.absoluteString,
                    validator: HTTPRangeSupport.validator(from: http),
                    expectedBytes: expectedTotal
                ).save(to: context.stateURL)
            case let .chunk(data):
                guard let handle else { continue }
                try handle.write(contentsOf: data)
                bytesOnDisk += Int64(data.count)
                context.progress(ResumableDownloadProgress(bytesOnDisk: bytesOnDisk, expectedBytes: expectedTotal))
            }
        }

        guard sawResponse else { throw ResumableDownloadError.invalidResponse }
        try handle?.close()
        handle = nil
        if let expectedTotal, bytesOnDisk < expectedTotal {
            // The connection closed cleanly before all advertised bytes came
            // through. Keep the partial; the next attempt resumes from here.
            throw ResumableDownloadError.truncatedTransfer(received: bytesOnDisk, expected: expectedTotal)
        }

        // Promote the finished partial and drop the resume record.
        try? fileManager.removeItem(at: context.destination)
        try fileManager.moveItem(at: context.partialURL, to: context.destination)
        try? fileManager.removeItem(at: context.stateURL)
    }

    /// What to do with a response, given the offset the attempt asked to
    /// resume from.
    private enum Disposition {
        case append(expectedTotal: Int64?)
        case restart(expectedTotal: Int64?)
        case stale
        case failure(Int)
    }

    private static func disposition(for response: HTTPURLResponse, resumeOffset: Int64) -> Disposition {
        switch response.statusCode {
        case 206:
            // Only honor a partial response that starts exactly where our
            // bytes end; anything else would corrupt the file.
            guard resumeOffset > 0,
                  let range = HTTPRangeSupport.parseContentRange(
                      response.value(forHTTPHeaderField: "Content-Range")
                  ),
                  range.start == resumeOffset
            else { return .stale }
            return .append(expectedTotal: range.total)
        case 200:
            // Full response: either a clean start, or the server declined the
            // range (e.g. the If-Range validator no longer matches).
            let length = response.expectedContentLength
            return .restart(expectedTotal: length >= 0 ? length : nil)
        case 416:
            // Requested range not satisfiable: our partial is useless.
            return .stale
        default:
            return .failure(response.statusCode)
        }
    }

    private static func fileSize(at url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}
