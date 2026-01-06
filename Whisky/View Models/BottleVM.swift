//
//  BottleVM.swift
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
import SemanticVersion
import WhiskyKit
import os.log

// MARK: - Bottle Creation Errors

enum BottleCreationError: LocalizedError {
    case directoryCreationFailed
    case metadataCreationFailed
    case wineVersionChangeFailed
    case persistenceSaveFailed

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Failed to create bottle directory"
        case .metadataCreationFailed:
            return "Failed to create bottle metadata"
        case .wineVersionChangeFailed:
            return "Failed to configure Windows version"
        case .persistenceSaveFailed:
            return "Failed to save bottle to persistence"
        }
    }
}

private let bottleVMLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.franke.Whisky",
    category: "BottleVM"
)

@MainActor
final class BottleVM: ObservableObject {
    static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []

    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task {
            var bottleId: Bottle?
            do {
                // Create directory with proper error handling (FileManager is thread-safe)
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: newBottleDir,
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)

                // Verify directory was created
                guard fileManager.fileExists(atPath: newBottleDir.path(percentEncoded: false)) else {
                    throw BottleCreationError.directoryCreationFailed
                }

                // Create bottle on main actor (since Bottle is @MainActor)
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle
                self.bottles.append(bottle)

                // Configure bottle settings (all on MainActor)
                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName

                // Wine operations are async and can run on background threads
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

                // Save settings
                bottle.saveBottleSettings()

                // Add record to persistence
                if !self.bottlesList.paths.contains(newBottleDir) {
                    self.bottlesList.paths.append(newBottleDir)
                }
                self.loadBottles()
            } catch {
                bottleVMLogger.error("Failed to create new bottle: \(error.localizedDescription)")
                // Clean up on failure
                if let bottle = bottleId {
                    if let index = self.bottles.firstIndex(of: bottle) {
                        self.bottles.remove(at: index)
                    }
                }
                // Try to clean up the directory
                try? FileManager.default.removeItem(at: newBottleDir)
            }
        }
        return newBottleDir
    }
}
