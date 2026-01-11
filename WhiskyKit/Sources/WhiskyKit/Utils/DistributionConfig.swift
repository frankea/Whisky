//
//  DistributionConfig.swift
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

public enum DistributionConfig {
    /// Base URL for GitHub Pages distribution
    public static let baseURL = "https://frankea.github.io/Whisky"

    /// URL for the WhiskyWine version plist file
    public static let versionPlistURL = "\(baseURL)/WhiskyWineVersion.plist"

    /// Base URL for GitHub Releases downloads
    public static let releasesBaseURL = "https://github.com/frankea/Whisky/releases/download"

    /// URL for the Sparkle appcast feed
    public static let appcastURL = "\(baseURL)/appcast.xml"

    /// Constructs the download URL for Wine Libraries from GitHub Releases
    /// - Parameter version: The version string (e.g., "2.5.0")
    /// - Returns: The full URL to download Libraries.tar.gz from GitHub Releases
    public static func librariesURL(version: String) -> String {
        return "\(releasesBaseURL)/v\(version)/Libraries.tar.gz"
    }
}
