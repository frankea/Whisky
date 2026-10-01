//
//  WinePrefixBootstrap.swift
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
import os.log
import SemanticVersion

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WinePrefixBootstrap")

/// Errors thrown when a bottle's Wine prefix cannot be set up before a launch.
public enum WinePrefixBootstrapError: LocalizedError, Equatable {
    /// The Wine runtime the prefix is created with isn't installed.
    case runtimeMissing
    /// Wine ran, but the prefix still has no `system32` afterwards.
    case incomplete

    public var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            String(
                localized: "wine.prefix.bootstrap.runtimeMissing",
                defaultValue: """
                This bottle's Wine prefix can't be set up because the Wine runtime isn't installed. \
                Open Whisky to install it, then try again.
                """
            )
        case .incomplete:
            String(
                localized: "wine.prefix.bootstrap.incomplete",
                defaultValue: """
                This bottle's Wine prefix couldn't be set up, so nothing can run in it yet. \
                The latest Wine log has the details.
                """
            )
        }
    }
}

public extension Wine {
    /// Sets up a bottle's Wine prefix, the work ``prepareBottlePrefix(bottle:bootstrapper:)``
    /// hands off when the prefix is missing. Tests pass a recorder in its place.
    typealias PrefixBootstrapper = @MainActor (Bottle) async throws -> Void

    /// Whether the bottle's Wine prefix has been created.
    ///
    /// Keys on `drive_c/windows/system32`, the folder launch preparation deploys
    /// the graphics backend's files into. A bottle made by `WhiskyCmd create`
    /// has its folder and metadata but no prefix until Wine first runs in it.
    ///
    /// - Parameter bottle: The bottle to check.
    /// - Returns: `true` once the prefix has a `system32` folder.
    @MainActor
    static func isPrefixBootstrapped(_ bottle: Bottle) -> Bool {
        let system32 = bottle.url.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: system32.path(percentEncoded: false), isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    /// Creates the bottle's Wine prefix when it doesn't exist yet.
    ///
    /// Launches call this before they prepare the bottle, since preparation
    /// writes into the prefix. A bottle that already has one is left alone, so
    /// for bottles made in the app this only checks for a folder.
    ///
    /// - Parameters:
    ///   - bottle: The bottle about to be launched in.
    ///   - bootstrapper: What creates the prefix. Defaults to the same Wine
    ///     invocation the app runs when it creates a bottle.
    /// - Throws: ``WinePrefixBootstrapError/runtimeMissing`` without a Wine runtime,
    ///   ``WinePrefixBootstrapError/incomplete`` when the prefix is still missing
    ///   afterwards, or the bootstrapper's own error.
    @MainActor
    static func prepareBottlePrefix(
        bottle: Bottle, bootstrapper: PrefixBootstrapper = { try await bootstrapPrefix(bottle: $0) }
    ) async throws {
        guard !isPrefixBootstrapped(bottle) else { return }

        logger.info("Bootstrapping the Wine prefix of bottle '\(bottle.settings.name, privacy: .public)'")
        try await bootstrapper(bottle)

        guard isPrefixBootstrapped(bottle) else {
            throw WinePrefixBootstrapError.incomplete
        }
    }

    /// Creates a bottle's Wine prefix the way the app does for a new bottle.
    ///
    /// Sets the bottle's Windows version with `winecfg`, which has Wine create
    /// the prefix first, records the runtime version in the bottle settings and
    /// copies the host fonts in.
    ///
    /// - Parameter bottle: The bottle whose prefix to create.
    /// - Throws: ``WinePrefixBootstrapError/runtimeMissing`` without a Wine runtime,
    ///   or an error if Wine cannot be run.
    @MainActor
    static func bootstrapPrefix(bottle: Bottle) async throws {
        guard WhiskyWineInstaller.isWhiskyWineInstalled() else {
            throw WinePrefixBootstrapError.runtimeMissing
        }

        try await changeWinVersion(bottle: bottle, win: bottle.settings.windowsVersion)
        if let version = try? await wineVersion(), let semantic = SemanticVersion(version) {
            bottle.settings.wineVersion = semantic
        }
        BottleFontBootstrap.copySystemFonts(toPrefix: bottle.url)
    }
}
