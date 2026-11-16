//
//  DownloadResponseSummary.swift
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

/// What a setup download got back when the body wasn't the file Whisky asked for.
///
/// Network filters, firewalls and Wi-Fi sign-in pages often answer a blocked
/// request with their own web page and a success status, so the problem only
/// shows when the body fails to parse. This keeps enough to tell that apart
/// from a broken file on the server, without keeping the page itself: a
/// filter's page, its path and its query can name the user. Only the host
/// that answered is kept, to tell a local filter or portal from GitHub.
public struct DownloadResponseSummary: Codable, Equatable, Sendable {
    /// How many leading bytes are inspected for HTML markers.
    static let sniffLength = 2_048

    /// The MIME type the server declared, if any.
    public let mimeType: String?
    /// The host that finally answered, only when redirects moved the request
    /// off the requested host. Host only, never the path or query.
    public let redirectedHost: String?
    /// Size of the body in bytes.
    public let byteCount: Int
    /// Whether the declared type or the body itself is an HTML page.
    public let isWebPage: Bool

    /// Summarizes an in-memory response body.
    ///
    /// - Parameters:
    ///   - data: The response body.
    ///   - response: The response, used for its MIME type and final URL.
    ///   - requestedURL: The URL that was requested, to spot redirects to another host.
    public init(data: Data, response: URLResponse?, requestedURL: URL) {
        let mimeType = response?.mimeType
        self.mimeType = mimeType
        redirectedHost = Self.redirectedHost(finalURL: response?.url, requestedURL: requestedURL)
        byteCount = data.count
        isWebPage = Self.looksLikeWebPage(data.prefix(Self.sniffLength), mimeType: mimeType)
    }

    /// Summarizes a downloaded file by its leading bytes, for downloads that go
    /// straight to disk and no longer have their response at hand.
    ///
    /// - Parameter fileURL: The downloaded file.
    /// - Returns: `nil` when the file can't be read.
    public init?(fileAt fileURL: URL) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: Self.sniffLength),
              let size = try? handle.seekToEnd()
        else { return nil }
        mimeType = nil
        redirectedHost = nil
        byteCount = Int(clamping: size)
        isWebPage = Self.looksLikeWebPage(prefix, mimeType: nil)
    }

    /// One line for the setup diagnostics, for example
    /// `text/html, 5120 bytes, web page, answered by filter.example.org`.
    public var diagnosticDescription: String {
        var parts = [mimeType ?? "no content type", "\(byteCount) bytes"]
        if isWebPage {
            parts.append("web page")
        }
        if let redirectedHost {
            parts.append("answered by \(redirectedHost)")
        }
        return parts.joined(separator: ", ")
    }

    /// Whether a body is an HTML page rather than a property list or archive.
    ///
    /// An HTML MIME type is enough on its own. Otherwise the leading bytes are
    /// checked for an HTML doctype or `<html` tag; property lists (XML or
    /// binary) and gzip archives never contain either near the start.
    ///
    /// - Parameters:
    ///   - prefix: The leading bytes of the body.
    ///   - mimeType: The declared MIME type, if known.
    static func looksLikeWebPage(_ prefix: Data, mimeType: String?) -> Bool {
        if let mimeType = mimeType?.lowercased(),
           mimeType == "text/html" || mimeType == "application/xhtml+xml" {
            return true
        }
        // Latin-1 maps every byte, so binary bodies and a multi-byte character
        // cut at the boundary still decode; the markers are plain ASCII.
        let text = (String(bytes: prefix.prefix(sniffLength), encoding: .isoLatin1) ?? "").lowercased()
        return text.contains("<!doctype html") || text.contains("<html")
    }

    private static func redirectedHost(finalURL: URL?, requestedURL: URL) -> String? {
        guard let finalHost = finalURL?.host(percentEncoded: false)?.lowercased(),
              !finalHost.isEmpty
        else { return nil }
        let requestedHost = requestedURL.host(percentEncoded: false)?.lowercased()
        return finalHost == requestedHost ? nil : finalHost
    }
}
