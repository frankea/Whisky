//
//  AppSteamClientDriver.swift
//  Whisky
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
import WhiskyKit

/// The kit's Wine-backed driver plus the one thing that is the app's business:
/// Steam download monitoring for the session, started when the client is up
/// and stopped with the orchestrator.
@MainActor
final class AppSteamClientDriver: WineSteamClientDriver {
    private let downloadMonitor = SteamDownloadMonitor()

    override func clientDidBecomeReady() {
        guard !downloadMonitor.isMonitoring else { return }
        downloadMonitor.startMonitoring(bottleURL: bottle.url, detectedLauncher: .steam)
    }

    override func shutdown() {
        downloadMonitor.stopMonitoring()
    }
}
