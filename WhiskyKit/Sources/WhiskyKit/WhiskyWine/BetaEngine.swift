//
//  BetaEngine.swift
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
import SemanticVersion

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "BetaEngine")

/// A Wine Libraries build published on GitHub Releases that can be installed
/// in place of the engine the version feed names.
public struct EngineRelease: Equatable, Sendable {
    /// The release tag, such as `v4.8.5-beta.1`.
    public let tag: String
    /// The version the tag names, including its pre-release part.
    public let version: SemanticVersion
    /// Where `Libraries.tar.gz` downloads from.
    public let downloadURL: URL
    /// The archive's SHA-256 as lowercase hex, from the asset digest GitHub
    /// computes on upload.
    public let sha256: String
    /// The release page, where the notes say what changed and what to test.
    public let notesURL: URL

    public init(tag: String, version: SemanticVersion, downloadURL: URL, sha256: String, notesURL: URL) {
        self.tag = tag
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.notesURL = notesURL
    }
}

/// What the app recorded about a beta engine it installed.
///
/// Engine plists stamp only `major.minor.patch`, so a beta reads the same as
/// the stable build it later becomes. This record is how the app tells them
/// apart. It lives inside `Libraries/`, so installing any other engine
/// (an update, a reinstall, a switch back to stable) removes it with the
/// runtime it described.
public struct InstalledBetaRecord: Codable, Equatable, Sendable {
    /// The release tag, such as `v4.8.5-beta.1`.
    public let tag: String
    /// The release page, kept so Settings can link to it offline.
    public let notesURL: URL

    public init(tag: String, notesURL: URL) {
        self.tag = tag
        self.notesURL = notesURL
    }

    /// The version the tag names, or `nil` when the tag is not a version.
    public var version: SemanticVersion? {
        BetaEngine.version(fromTag: tag)
    }

    /// Whether a stable engine at `stable` already carries this beta, which
    /// is true once the beta was promoted or a newer stable build shipped.
    /// Betas stamp the version they are a candidate for (4.8.5-beta.1 is a
    /// candidate for 4.8.5), so the comparison drops the pre-release part.
    public func isSuperseded(byStable stable: SemanticVersion) -> Bool {
        guard let version else { return false }
        return SemanticVersion(version.major, version.minor, version.patch) <= stable
    }
}

/// Finding, installing, and leaving the opt-in beta engine.
///
/// Betas are the Wine Libraries prereleases on GitHub Releases (bare `v` tags;
/// app releases use `app-v`). Only a beta newer than the stable engine the
/// version feed names is offered, so a beta that has since been promoted, or
/// superseded by a newer stable build, never shows up.
public enum BetaEngine {
    /// The GitHub API listing of the repository's releases, newest first.
    public static let releasesAPIURL = URL(string: "https://api.github.com/repos/frankea/Whisky/releases?per_page=50")

    /// The name of the record ``recordInstalled(_:)`` writes into `Libraries/`.
    static let recordFileName = "WhiskyWineBeta.plist"

    /// The engine archive every Wine Libraries release carries.
    static let archiveAssetName = "Libraries.tar.gz"

    // MARK: - Finding the latest beta

    /// Errors from ``fetchLatestBeta(session:)``.
    public enum FetchError: LocalizedError, Equatable {
        /// GitHub answered with a non-success status, such as 403 when the
        /// unauthenticated rate limit is used up.
        case httpStatus(Int)
        /// The stable feed could not be read, so there is nothing to compare
        /// a beta against.
        case stableVersionUnavailable

        public var errorDescription: String? {
            switch self {
            case let .httpStatus(code):
                String(format: String(localized: "settings.betaEngine.error.http"), code)
            case .stableVersionUnavailable:
                String(localized: "settings.betaEngine.error.stableUnknown")
            }
        }
    }

    /// Fetches the newest beta that is newer than the stable engine.
    ///
    /// - Returns: The beta to offer, or `nil` when none is newer than stable.
    public static func fetchLatestBeta(session: URLSession = URLSession(configuration: .ephemeral))
        async throws -> EngineRelease? {
        guard let stable = try await fetchStableVersion(session: session) else {
            throw FetchError.stableVersionUnavailable
        }
        guard let releasesAPIURL else { return nil }
        var request = URLRequest(url: releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        return latestBeta(inReleasesJSON: data, newerThan: stable)
    }

    /// The version the stable feed names, which is what the app installs and
    /// offers as an update.
    public static func fetchStableVersion(session: URLSession = URLSession(configuration: .ephemeral))
        async throws -> SemanticVersion? {
        guard let url = URL(string: DistributionConfig.versionPlistURL) else { return nil }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }
        return try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data).version
    }

    /// Picks the newest installable beta out of a GitHub releases listing.
    ///
    /// A release counts when it is a published prerelease whose tag is a
    /// `v`-prefixed version with a pre-release part, and it carries
    /// `Libraries.tar.gz` with a SHA-256 digest. A beta without a digest is
    /// skipped rather than installed unverified.
    ///
    /// - Parameters:
    ///   - data: The JSON body of `GET /repos/{owner}/{repo}/releases`.
    ///   - stable: The version the stable feed names.
    /// - Returns: The newest qualifying beta that sorts above `stable`, or
    ///   `nil` when there is none or the JSON does not decode.
    public static func latestBeta(inReleasesJSON data: Data, newerThan stable: SemanticVersion) -> EngineRelease? {
        let releases: [GitHubRelease]
        do {
            releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        } catch {
            logger.warning("Could not decode the releases listing: \(error.localizedDescription)")
            return nil
        }
        return releases
            .compactMap(engineRelease(from:))
            .filter { stable < $0.version }
            .max { $0.version < $1.version }
    }

    /// The beta a listed release describes, or `nil` when it is not one.
    static func engineRelease(from release: GitHubRelease) -> EngineRelease? {
        guard release.prerelease, !release.draft,
              let version = version(fromTag: release.tagName), version.isPreRelease,
              let asset = release.assets.first(where: { $0.name == archiveAssetName }),
              let sha256 = sha256(fromDigest: asset.digest),
              let downloadURL = URL(string: asset.browserDownloadURL),
              let notesURL = URL(string: release.htmlURL)
        else { return nil }
        return EngineRelease(
            tag: release.tagName,
            version: version,
            downloadURL: downloadURL,
            sha256: sha256,
            notesURL: notesURL
        )
    }

    /// The version a Wine Libraries tag names: `v4.8.5-beta.1` gives
    /// 4.8.5-beta.1. App tags (`app-v…`) and anything else give `nil`.
    public static func version(fromTag tag: String) -> SemanticVersion? {
        guard tag.hasPrefix("v") else { return nil }
        return SemanticVersion(String(tag.dropFirst()))
    }

    /// The hex digest out of GitHub's `sha256:<hex>` asset digest, or `nil`
    /// for a missing digest, another algorithm, or a malformed value.
    static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return hex
    }

    // MARK: - Installed beta record

    /// The beta the installed engine came from, or `nil` for any other engine.
    public static func installedBeta() -> InstalledBetaRecord? {
        installedBeta(inLibraryFolder: WhiskyWineInstaller.libraryFolder)
    }

    static func installedBeta(inLibraryFolder folder: URL) -> InstalledBetaRecord? {
        let url = folder.appending(path: recordFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(InstalledBetaRecord.self, from: data)
    }

    /// Records that the engine just installed came from `release`. Call it
    /// after the install succeeded, since the record describes the runtime
    /// beside it.
    public static func recordInstalled(_ release: EngineRelease) throws {
        try recordInstalled(release, inLibraryFolder: WhiskyWineInstaller.libraryFolder)
    }

    static func recordInstalled(_ release: EngineRelease, inLibraryFolder folder: URL) throws {
        let record = InstalledBetaRecord(tag: release.tag, notesURL: release.notesURL)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(record).write(to: folder.appending(path: recordFileName), options: .atomic)
    }
}

// MARK: - GitHub releases JSON

/// The fields of a GitHub release ``BetaEngine`` needs.
struct GitHubRelease: Decodable {
    let tagName: String
    let prerelease: Bool
    let draft: Bool
    let htmlURL: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
        case draft
        case htmlURL = "html_url"
        case assets
    }
}

/// The fields of a release asset ``BetaEngine`` needs.
struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    /// `sha256:<hex>`, present on assets uploaded since mid-2025.
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}
