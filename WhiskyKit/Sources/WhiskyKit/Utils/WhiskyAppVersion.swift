//
//  WhiskyAppVersion.swift
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

/// The version of the Whisky app this process belongs to.
///
/// The app reads it from its own bundle. `WhiskyCmd` is a bare executable in
/// the app's `Contents/Resources`, so its main bundle has no Info.plist to
/// read; it reads the app's instead, found from where the executable really
/// is. That holds through the `/usr/local/bin/whisky` symlink the app installs.
///
/// The CLI is deliberately not given an embedded Info.plist of its own: that
/// would give it a bundle identifier, and `Bundle.whiskyBundleIdentifier`,
/// which names the folders the app and the CLI share, falls back to the app's
/// only while the CLI has none.
enum WhiskyAppVersion {
    static let versionKey = "CFBundleShortVersionString"

    /// This process's app version, or an empty string when there is none to
    /// find (a test runner, or a CLI binary copied out of the app).
    static let current: String = shortVersion(
        mainInfo: Bundle.main.infoDictionary, executableURL: Bundle.main.executableURL
    )

    /// The main bundle's own version when it has one, as the app's does;
    /// otherwise the version of the app enclosing `executableURL`.
    static func shortVersion(mainInfo: [String: Any]?, executableURL: URL?) -> String {
        if let version = mainInfo?[versionKey] as? String, !version.isEmpty {
            return version
        }
        guard let executableURL, let appInfo = enclosingAppInfo(ofExecutableAt: executableURL) else { return "" }
        return appInfo[versionKey] as? String ?? ""
    }

    /// The Info.plist of the nearest `.app` folder above an executable, after
    /// resolving symlinks, or `nil` when it is not inside one.
    static func enclosingAppInfo(ofExecutableAt executableURL: URL) -> [String: Any]? {
        var folder = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
        while folder.path(percentEncoded: false) != "/" {
            if folder.pathExtension.lowercased() == "app" {
                let plistURL = folder.appending(path: "Contents").appending(path: "Info.plist")
                guard let data = try? Data(contentsOf: plistURL) else { return nil }
                return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }
}
