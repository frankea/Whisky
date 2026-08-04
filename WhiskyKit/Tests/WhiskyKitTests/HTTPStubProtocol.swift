//
//  HTTPStubProtocol.swift
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

import Foundation

/// A `URLProtocol` stub that answers every request from a test-provided
/// handler, recording each request it sees. Install it via
/// `URLSessionConfiguration.protocolClasses` so downloader tests run fully
/// offline and deterministically.
final class HTTPStubProtocol: URLProtocol {
    /// One scripted response.
    struct StubResponse {
        var statusCode: Int
        var headers: [String: String] = [:]
        var body = Data()
        /// When set, deliver only this many body bytes and then interrupt.
        var deliverOnly: Int?
        /// How to interrupt after `deliverOnly` bytes: finish the response
        /// cleanly (a truncated close) when `true`, else fail with
        /// `URLError.networkConnectionLost`.
        var finishEarlyAfterPartialBody = false
    }

    typealias Handler = @Sendable (URLRequest) -> StubResponse

    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedHandler: Handler?
    private nonisolated(unsafe) static var storedRequests: [URLRequest] = []

    static var handler: Handler? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    /// Every request seen since the last `reset()`, in arrival order.
    static var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    static func reset() {
        lock.withLock {
            storedHandler = nil
            storedRequests = []
        }
    }

    private static func record(_ request: URLRequest) {
        lock.withLock { storedRequests.append(request) }
    }

    private let stateLock = NSLock()
    private var isStopped = false

    // URLProtocol declares these as class funcs, so `static` is not an option.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        Self.record(request)
        let stub = handler(request)

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: stub.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if let limit = stub.deliverOnly {
            let partial = stub.body.prefix(limit)
            if !partial.isEmpty {
                client?.urlProtocol(self, didLoad: Data(partial))
            }
            if stub.finishEarlyAfterPartialBody {
                client?.urlProtocolDidFinishLoading(self)
            } else {
                // Fail on a delay: an error reported in the same turn as the
                // final data chunk makes URLSession drop the not-yet-delivered
                // bytes, which would make the interruption tests start the
                // resume from byte zero.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, !self.stateLock.withLock({ self.isStopped }) else { return }
                    client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                }
            }
        } else {
            if !stub.body.isEmpty {
                client?.urlProtocol(self, didLoad: stub.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        stateLock.withLock { isStopped = true }
    }
}

/// A tiny thread-safe attempt counter for scripting per-request behavior.
final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Returns the 1-based number of this call.
    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
