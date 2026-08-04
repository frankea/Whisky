//
//  ResumableDownloaderTests.swift
//  WhiskyKitTests
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

// swiftlint:disable file_length

import CryptoKit
@testable import WhiskyKit
import XCTest

/// Collects progress values across concurrency domains.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64] = []

    func append(_ value: Int64) {
        lock.withLock { values.append(value) }
    }

    var all: [Int64] {
        lock.withLock { values }
    }
}

// swiftlint:disable:next type_body_length
final class ResumableDownloaderTests: XCTestCase {
    private var tempDir: URL!
    private var destination: URL!
    private let sourceURL = URL(string: "https://example.test/Libraries.tar.gz") ?? URL(fileURLWithPath: "/")

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ResumableDownloaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        destination = tempDir.appending(path: "Libraries.tar.gz")
        HTTPStubProtocol.reset()
    }

    override func tearDownWithError() throws {
        HTTPStubProtocol.reset()
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private var partialURL: URL { ResumableDownloader.partialURL(for: destination) }
    private var stateURL: URL { ResumableDownloader.resumeStateURL(for: destination) }

    private func makeDownloader(
        maxAttempts: Int = 4,
        initialRetryDelay: TimeInterval = 0.02
    ) -> ResumableDownloader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStubProtocol.self]
        return ResumableDownloader(
            sessionConfiguration: config,
            retryPolicy: ResumableDownloadRetryPolicy(
                maxAttempts: maxAttempts,
                initialRetryDelay: initialRetryDelay,
                maxRetryDelay: 0.1
            )
        )
    }

    /// Deterministic pseudo-random payload so byte-identity failures are real.
    private static func makePayload(length: Int, seed: UInt64 = 42) -> Data {
        var state = seed
        var data = Data(capacity: length)
        for _ in 0 ..< length {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            data.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        return data
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Serves `payload` like a static file server with byte-range support.
    /// `script` can override individual requests (1-based) to fault-inject.
    private static func installRangeServer(
        payload: Data,
        etag: String = "\"etag-1\"",
        script: @escaping @Sendable (Int, URLRequest) -> HTTPStubProtocol.StubResponse? = { _, _ in nil }
    ) {
        let counter = RequestCounter()
        HTTPStubProtocol.handler = { request in
            if let scripted = script(counter.next(), request) {
                return scripted
            }
            return serve(payload: payload, etag: etag, request: request)
        }
    }

    private static func serve(payload: Data, etag: String, request: URLRequest) -> HTTPStubProtocol.StubResponse {
        let ifRange = request.value(forHTTPHeaderField: "If-Range")
        if let rangeHeader = request.value(forHTTPHeaderField: "Range"),
           let offsetPart = rangeHeader.split(separator: "=").last?.split(separator: "-").first,
           let offset = Int(offsetPart),
           ifRange == nil || ifRange == etag {
            guard offset < payload.count else {
                return HTTPStubProtocol.StubResponse(
                    statusCode: 416,
                    headers: ["Content-Range": "bytes */\(payload.count)", "ETag": etag]
                )
            }
            let body = payload.subdata(in: offset ..< payload.count)
            return HTTPStubProtocol.StubResponse(
                statusCode: 206,
                headers: [
                    "Content-Range": "bytes \(offset)-\(payload.count - 1)/\(payload.count)",
                    "Content-Length": "\(body.count)",
                    "ETag": etag
                ],
                body: body
            )
        }
        return HTTPStubProtocol.StubResponse(
            statusCode: 200,
            headers: ["Content-Length": "\(payload.count)", "ETag": etag],
            body: payload
        )
    }

    private func rangeHeader(ofRequest index: Int) -> String? {
        let requests = HTTPStubProtocol.requests
        guard index < requests.count else { return nil }
        return requests[index].value(forHTTPHeaderField: "Range")
    }

    private func assertNoInFlightArtifacts(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: partialURL.path), "partial should be gone", file: file, line: line
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: stateURL.path), "resume state should be gone", file: file, line: line
        )
    }

    // MARK: - Clean download

    func testCleanDownloadWritesExactBytes() async throws {
        let payload = Self.makePayload(length: 256 * 1_024)
        Self.installRangeServer(payload: payload)

        try await makeDownloader().download(from: sourceURL, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(HTTPStubProtocol.requests.count, 1)
        XCTAssertNil(rangeHeader(ofRequest: 0), "clean download must not send a Range header")
        assertNoInFlightArtifacts()
    }

    // MARK: - Interrupt and resume

    func testInterruptedDownloadResumesAndMatchesByteIdentical() async throws {
        let payload = Self.makePayload(length: 256 * 1_024)
        Self.installRangeServer(payload: payload) { requestNumber, request in
            guard requestNumber == 1 else { return nil }
            var stub = Self.serve(payload: payload, etag: "\"etag-1\"", request: request)
            stub.deliverOnly = 96 * 1_024
            return stub
        }
        let progressLog = ProgressLog()

        try await makeDownloader().download(from: sourceURL, to: destination, progress: { progress in
            progressLog.append(progress.bytesOnDisk)
        })

        XCTAssertEqual(try Data(contentsOf: destination), payload, "resumed file must be byte-identical")
        XCTAssertEqual(HTTPStubProtocol.requests.count, 2)
        let resumeRange = try XCTUnwrap(rangeHeader(ofRequest: 1), "second request should resume with a Range header")
        XCTAssertTrue(resumeRange.hasPrefix("bytes="))
        let resumeOffset = try XCTUnwrap(Int64(resumeRange.dropFirst("bytes=".count).dropLast()))
        XCTAssertGreaterThan(resumeOffset, 0)
        let observed = progressLog.all
        XCTAssertEqual(observed, observed.sorted(), "progress must never go backwards")
        XCTAssertEqual(observed.last, Int64(payload.count))
        assertNoInFlightArtifacts()
    }

    func testResumeSurvivesDownloaderRelaunch() async throws {
        let payload = Self.makePayload(length: 256 * 1_024)
        Self.installRangeServer(payload: payload) { requestNumber, request in
            guard requestNumber == 1 else { return nil }
            var stub = Self.serve(payload: payload, etag: "\"etag-1\"", request: request)
            stub.deliverOnly = 128 * 1_024
            return stub
        }

        // First "launch": no retry budget, so the interruption surfaces.
        do {
            try await makeDownloader(maxAttempts: 1).download(from: sourceURL, to: destination)
            XCTFail("interrupted download should throw")
        } catch {
            XCTAssertTrue(ResumableDownloader.isTransient(error), "interruption should be a transient error")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: partialURL.path), "partial must survive for resume")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path), "resume state must survive")

        // Second "launch": a fresh instance picks up the on-disk state.
        try await makeDownloader().download(from: sourceURL, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertNotNil(rangeHeader(ofRequest: 1), "relaunched download should resume, not restart")
        assertNoInFlightArtifacts()
    }

    // MARK: - Resume invalidation

    func testStaleValidatorFallsBackToFreshStart() async throws {
        let payload = Self.makePayload(length: 128 * 1_024)
        // Seed a partial from an older release of the asset.
        try Data(repeating: 0xAB, count: 100).write(to: partialURL)
        ResumeState(urlString: sourceURL.absoluteString, validator: "\"old\"", expectedBytes: nil).save(to: stateURL)
        Self.installRangeServer(payload: payload, etag: "\"new\"")

        try await makeDownloader().download(from: sourceURL, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload, "stale partial must not leak into the result")
        XCTAssertEqual(HTTPStubProtocol.requests.count, 1)
        XCTAssertNotNil(rangeHeader(ofRequest: 0), "resume should have been attempted")
        assertNoInFlightArtifacts()
    }

    func testRangeNotSatisfiableDiscardsPartialAndRestartsClean() async throws {
        let payload = Self.makePayload(length: 128 * 1_024)
        try Data(repeating: 0xCD, count: 100).write(to: partialURL)
        ResumeState(urlString: sourceURL.absoluteString, validator: nil, expectedBytes: nil).save(to: stateURL)
        Self.installRangeServer(payload: payload) { requestNumber, _ in
            guard requestNumber == 1 else { return nil }
            return HTTPStubProtocol.StubResponse(
                statusCode: 416,
                headers: ["Content-Range": "bytes */\(payload.count)"]
            )
        }

        try await makeDownloader().download(from: sourceURL, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(HTTPStubProtocol.requests.count, 2)
        XCTAssertNotNil(rangeHeader(ofRequest: 0))
        XCTAssertNil(rangeHeader(ofRequest: 1), "after 416 the retry must start clean")
        assertNoInFlightArtifacts()
    }

    func testPartialForDifferentURLIsDiscarded() async throws {
        let payload = Self.makePayload(length: 64 * 1_024)
        try Data(repeating: 0xEF, count: 100).write(to: partialURL)
        ResumeState(
            urlString: "https://example.test/v-old/Libraries.tar.gz", validator: "\"e\"", expectedBytes: nil
        ).save(to: stateURL)
        Self.installRangeServer(payload: payload)

        try await makeDownloader().download(from: sourceURL, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertNil(rangeHeader(ofRequest: 0), "a partial for another URL must not be resumed")
        assertNoInFlightArtifacts()
    }

    // MARK: - Truncated close

    func testTruncatedCleanCloseResumesOnRetry() async throws {
        let payload = Self.makePayload(length: 128 * 1_024)
        Self.installRangeServer(payload: payload) { requestNumber, request in
            guard requestNumber == 1 else { return nil }
            var stub = Self.serve(payload: payload, etag: "\"etag-1\"", request: request)
            stub.deliverOnly = 64 * 1_024
            stub.finishEarlyAfterPartialBody = true
            return stub
        }

        try await makeDownloader().download(from: sourceURL, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(HTTPStubProtocol.requests.count, 2)
        XCTAssertEqual(rangeHeader(ofRequest: 1), "bytes=\(64 * 1_024)-")
        assertNoInFlightArtifacts()
    }

    // MARK: - Retry and backoff

    func testTransientServerErrorRetriesUntilSuccess() async throws {
        let payload = Self.makePayload(length: 64 * 1_024)
        Self.installRangeServer(payload: payload) { requestNumber, _ in
            guard requestNumber <= 2 else { return nil }
            return HTTPStubProtocol.StubResponse(statusCode: 503)
        }

        try await makeDownloader(maxAttempts: 4).download(from: sourceURL, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(HTTPStubProtocol.requests.count, 3)
    }

    func testRetriesExhaustedThrowsLastError() async {
        Self.installRangeServer(payload: Data()) { _, _ in
            HTTPStubProtocol.StubResponse(statusCode: 503)
        }

        do {
            try await makeDownloader(maxAttempts: 2).download(from: sourceURL, to: destination)
            XCTFail("download should fail once the attempt budget is spent")
        } catch {
            XCTAssertEqual(error as? ResumableDownloadError, .httpStatus(503))
        }
        XCTAssertEqual(HTTPStubProtocol.requests.count, 2, "budget of 2 attempts means exactly 2 requests")
    }

    func testPermanentHTTPErrorFailsWithoutRetry() async {
        Self.installRangeServer(payload: Data()) { _, _ in
            HTTPStubProtocol.StubResponse(statusCode: 404)
        }

        do {
            try await makeDownloader(maxAttempts: 4).download(from: sourceURL, to: destination)
            XCTFail("404 should fail immediately")
        } catch {
            XCTAssertEqual(error as? ResumableDownloadError, .httpStatus(404))
        }
        XCTAssertEqual(HTTPStubProtocol.requests.count, 1, "permanent errors must not be retried")
    }

    func testCancellationDuringBackoffPreservesPartialAndThrowsCancellation() async throws {
        let payload = Self.makePayload(length: 128 * 1_024)
        Self.installRangeServer(payload: payload) { requestNumber, request in
            guard requestNumber == 1 else { return nil }
            var stub = Self.serve(payload: payload, etag: "\"etag-1\"", request: request)
            stub.deliverOnly = 64 * 1_024
            return stub
        }

        // Long backoff so cancellation lands during the sleep.
        let downloader = makeDownloader(maxAttempts: 3, initialRetryDelay: 30)
        let sourceURL = sourceURL
        let destination = try XCTUnwrap(destination)
        let task = Task {
            try await downloader.download(from: sourceURL, to: destination)
        }
        while HTTPStubProtocol.requests.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            try await task.value
            XCTFail("cancelled download should throw")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: partialURL.path),
            "cancellation must keep the partial for a later resume"
        )
    }

    // MARK: - Integrity gate interplay

    func testHashMismatchDiscardThenCleanRedownload() async throws {
        let goodPayload = Self.makePayload(length: 64 * 1_024)
        var corrupted = goodPayload
        corrupted[1_000] ^= 0xFF
        let expectedHash = Self.sha256Hex(of: goodPayload)
        let corruptedBody = corrupted

        // First download: server hands out corrupted bytes.
        Self.installRangeServer(payload: corruptedBody)
        try await makeDownloader().download(from: sourceURL, to: destination)
        XCTAssertEqual(
            WhiskyWineInstaller.integrityResult(forFileAt: destination, expectedSHA256: expectedHash),
            .mismatch(actual: Self.sha256Hex(of: corruptedBody))
        )

        // The caller-side gate discards everything on a mismatch.
        ResumableDownloader.discardArtifacts(at: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        assertNoInFlightArtifacts()

        // The re-download starts clean and verifies.
        HTTPStubProtocol.reset()
        Self.installRangeServer(payload: goodPayload)
        try await makeDownloader().download(from: sourceURL, to: destination)
        XCTAssertNil(rangeHeader(ofRequest: 0), "post-discard download must not resume")
        XCTAssertEqual(
            WhiskyWineInstaller.integrityResult(forFileAt: destination, expectedSHA256: expectedHash),
            .match
        )
    }

    // MARK: - Pure helpers

    func testParseContentRange() {
        XCTAssertNil(HTTPRangeSupport.parseContentRange(nil))
        XCTAssertNil(HTTPRangeSupport.parseContentRange("chunks 0-1/2"))
        let parsed = HTTPRangeSupport.parseContentRange("bytes 100-999/1000")
        XCTAssertEqual(parsed?.start, 100)
        XCTAssertEqual(parsed?.total, 1_000)
        let unknownTotal = HTTPRangeSupport.parseContentRange("bytes 5-9/*")
        XCTAssertEqual(unknownTotal?.start, 5)
        XCTAssertNil(unknownTotal?.total)
    }

    func testValidatorPrefersStrongETagAndSkipsWeak() throws {
        let strong = try XCTUnwrap(HTTPURLResponse(
            url: sourceURL, statusCode: 200, httpVersion: nil,
            headerFields: ["ETag": "\"abc\"", "Last-Modified": "yesterday"]
        ))
        XCTAssertEqual(HTTPRangeSupport.validator(from: strong), "\"abc\"")

        let weak = try XCTUnwrap(HTTPURLResponse(
            url: sourceURL, statusCode: 200, httpVersion: nil,
            headerFields: ["ETag": "W/\"abc\"", "Last-Modified": "yesterday"]
        ))
        XCTAssertEqual(HTTPRangeSupport.validator(from: weak), "yesterday")
    }

    func testRetryPolicyBackoffDoublesAndCaps() {
        let policy = ResumableDownloadRetryPolicy(maxAttempts: 6, initialRetryDelay: 1, maxRetryDelay: 5)
        XCTAssertEqual(policy.delay(beforeRetry: 1), 1)
        XCTAssertEqual(policy.delay(beforeRetry: 2), 2)
        XCTAssertEqual(policy.delay(beforeRetry: 3), 4)
        XCTAssertEqual(policy.delay(beforeRetry: 4), 5, "backoff must cap at maxRetryDelay")
        XCTAssertEqual(policy.delay(beforeRetry: 100), 5)
    }
}

// swiftlint:enable file_length
