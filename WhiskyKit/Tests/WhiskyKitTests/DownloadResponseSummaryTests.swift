//
//  DownloadResponseSummaryTests.swift
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
@testable import WhiskyKit
import XCTest

final class DownloadResponseSummaryTests: XCTestCase {
    private let requestedURL = URL(string: "https://frankea.github.io/Whisky/WhiskyWineVersion-v4.plist")
        ?? URL(fileURLWithPath: "/")
    private let blockPage = Data("""
    <!DOCTYPE html>
    <html><head><title>Blocked</title></head>
    <body>This site is blocked by your school's filter.</body></html>
    """.utf8)

    private func response(url: URL, mimeType: String?) -> URLResponse {
        URLResponse(url: url, mimeType: mimeType, expectedContentLength: -1, textEncodingName: nil)
    }

    private func versionPlistData() throws -> Data {
        let version = WhiskyWineVersion(version: .init(4, 8, 3), sha256: String(repeating: "a", count: 64))
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(version)
    }

    func testFilterPageServedAsHTMLIsAWebPage() {
        let summary = DownloadResponseSummary(
            data: blockPage,
            response: response(url: requestedURL, mimeType: "text/html"),
            requestedURL: requestedURL
        )
        XCTAssertTrue(summary.isWebPage)
        XCTAssertEqual(summary.mimeType, "text/html")
        XCTAssertEqual(summary.byteCount, blockPage.count)
        XCTAssertNil(summary.redirectedHost)
    }

    /// Some filters label their page as something other than HTML; the body still gives it away.
    func testFilterPageWithMisleadingTypeIsAWebPage() {
        let summary = DownloadResponseSummary(
            data: blockPage,
            response: response(url: requestedURL, mimeType: "application/octet-stream"),
            requestedURL: requestedURL
        )
        XCTAssertTrue(summary.isWebPage)
    }

    func testXHTMLTypeIsAWebPage() {
        XCTAssertTrue(DownloadResponseSummary.looksLikeWebPage(
            Data("<?xml version=\"1.0\"?>".utf8),
            mimeType: "Application/XHTML+XML"
        ))
    }

    func testXMLAndBinaryPlistsAreNotWebPages() throws {
        let xml = try versionPlistData()
        XCTAssertFalse(DownloadResponseSummary.looksLikeWebPage(xml, mimeType: "application/octet-stream"))

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let binary = try encoder.encode(WhiskyWineVersion(version: .init(4, 8, 3)))
        XCTAssertFalse(DownloadResponseSummary.looksLikeWebPage(binary, mimeType: nil))
    }

    func testGzipBytesAreNotAWebPage() {
        // gzip magic followed by bytes that are invalid UTF-8.
        let gzip = Data([0x1F, 0x8B, 0x08, 0x00, 0xFF, 0xFE, 0xC3, 0x28] + Array(repeating: 0x00, count: 64))
        XCTAssertFalse(DownloadResponseSummary.looksLikeWebPage(gzip, mimeType: nil))
    }

    func testRedirectToAnotherHostRecordsHostOnly() throws {
        let finalURL =
            try XCTUnwrap(URL(string: "https://filter.example.org/blocked?user=student42&url=frankea.github.io"))
        let summary = DownloadResponseSummary(
            data: blockPage,
            response: response(url: finalURL, mimeType: "text/html"),
            requestedURL: requestedURL
        )
        XCTAssertEqual(summary.redirectedHost, "filter.example.org")
        XCTAssertFalse(summary.diagnosticDescription.contains("student42"))
        XCTAssertFalse(summary.diagnosticDescription.contains("/blocked"))
        XCTAssertEqual(
            summary.diagnosticDescription,
            "text/html, \(blockPage.count) bytes, web page, answered by filter.example.org"
        )
    }

    func testSameHostIsNotReportedAsRedirect() throws {
        let summary = try DownloadResponseSummary(
            data: blockPage,
            response: response(url: XCTUnwrap(URL(string: "https://FRANKEA.github.io/other")), mimeType: nil),
            requestedURL: requestedURL
        )
        XCTAssertNil(summary.redirectedHost)
    }

    func testDescriptionWithoutTypeOrWebPage() {
        let summary = DownloadResponseSummary(data: Data("garbage".utf8), response: nil, requestedURL: requestedURL)
        XCTAssertFalse(summary.isWebPage)
        XCTAssertEqual(summary.diagnosticDescription, "no content type, 7 bytes")
    }

    func testMarkerPastSniffWindowIsIgnored() {
        var data = Data(repeating: 0x20, count: DownloadResponseSummary.sniffLength)
        data.append(Data("<html>".utf8))
        XCTAssertFalse(DownloadResponseSummary.looksLikeWebPage(data, mimeType: nil))
    }

    func testFileSummaryDetectsWebPageAndSize() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let page = directory.appending(path: "Libraries.tar.gz")
        try blockPage.write(to: page)
        let pageSummary = try XCTUnwrap(DownloadResponseSummary(fileAt: page))
        XCTAssertTrue(pageSummary.isWebPage)
        XCTAssertEqual(pageSummary.byteCount, blockPage.count)
        XCTAssertNil(pageSummary.mimeType)

        let archive = directory.appending(path: "real.tar.gz")
        var bytes = Data([0x1F, 0x8B, 0x08, 0x00])
        bytes.append(Data(repeating: 0x41, count: 10_000))
        try bytes.write(to: archive)
        let archiveSummary = try XCTUnwrap(DownloadResponseSummary(fileAt: archive))
        XCTAssertFalse(archiveSummary.isWebPage)
        XCTAssertEqual(archiveSummary.byteCount, bytes.count)

        XCTAssertNil(DownloadResponseSummary(fileAt: directory.appending(path: "missing")))
    }

    func testDiagnosticsReportIncludesResponsesAndRetryClearsThem() {
        var diagnostics = WhiskyWineSetupDiagnostics()
        let summary = DownloadResponseSummary(
            data: blockPage,
            response: response(url: requestedURL, mimeType: "text/html"),
            requestedURL: requestedURL
        )
        diagnostics.versionResponse = summary
        diagnostics.downloadResponse = summary

        let report = diagnostics.reportString(stage: "download")
        XCTAssertTrue(report.contains("Version plist response: \(summary.diagnosticDescription)"))
        XCTAssertTrue(report.contains("Download response: \(summary.diagnosticDescription)"))

        diagnostics.resetDownloadState(reason: "Retry requested")
        let afterRetry = diagnostics.reportString(stage: "download")
        XCTAssertFalse(afterRetry.contains("Version plist response"))
        XCTAssertFalse(afterRetry.contains("Download response"))
    }

    func testDiagnosticsDecodeWithoutResponseFields() throws {
        // Diagnostics encoded before these fields existed still decode.
        let diagnostics = WhiskyWineSetupDiagnostics()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(diagnostics)) as? [String: Any]
        )
        object.removeValue(forKey: "versionResponse")
        object.removeValue(forKey: "downloadResponse")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WhiskyWineSetupDiagnostics.self, from: data)
        XCTAssertNil(decoded.versionResponse)
        XCTAssertNil(decoded.downloadResponse)
    }
}
