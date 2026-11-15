//
//  RecordedLaunchTests.swift
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
import Testing
@testable import WhiskyKit

/// Collects launches from an observer block, which is `@Sendable`.
private final class LaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [RecordedLaunch] = []

    var launches: [RecordedLaunch] {
        lock.withLock { collected }
    }

    func append(_ launch: RecordedLaunch) {
        lock.withLock { collected.append(launch) }
    }
}

@Suite("Recorded Launch Tests")
struct RecordedLaunchTests {
    private let bottleURL = URL(fileURLWithPath: "/tmp/whisky-recorded-launch-test/Bottle")
    private let otherBottleURL = URL(fileURLWithPath: "/tmp/whisky-recorded-launch-test/Other")

    private func programEntry(_ path: String, in bottle: URL) -> LibraryEntry {
        let url = bottle.appending(path: path)
        return LibraryEntry(
            id: url.path, name: url.deletingPathExtension().lastPathComponent, iconURL: url,
            bottleURL: bottle, source: .pinned, launch: .program(url)
        )
    }

    private func steamEntry(_ appID: Int, in bottle: URL) -> LibraryEntry {
        LibraryEntry(
            id: "steam-\(appID)", name: "Game \(appID)", iconURL: nil,
            bottleURL: bottle, source: .steam, launch: .steam(appID: appID)
        )
    }

    @Test("A program launch is matched by bottle and file name, as its run log is keyed")
    func programMatching() {
        let launch = RecordedLaunch(bottleURL: bottleURL, target: .program(name: "Game.exe"), date: .now)

        #expect(launch.isLaunch(of: programEntry("drive_c/Game/Game.exe", in: bottleURL)))
        // Same file name elsewhere in the bottle: the run log cannot tell them apart either.
        #expect(launch.isLaunch(of: programEntry("drive_c/Copy/Game.exe", in: bottleURL)))
        #expect(!launch.isLaunch(of: programEntry("drive_c/Game/Other.exe", in: bottleURL)))
        #expect(!launch.isLaunch(of: programEntry("drive_c/Game/Game.exe", in: otherBottleURL)))
        #expect(!launch.isLaunch(of: steamEntry(440, in: bottleURL)))
    }

    @Test("Bottle paths are compared standardized")
    func standardizedBottle() {
        let unstandardized = URL(fileURLWithPath: "/tmp/whisky-recorded-launch-test/Other/../Bottle")
        let launch = RecordedLaunch(bottleURL: unstandardized, target: .program(name: "Game.exe"), date: .now)

        #expect(launch.isLaunch(of: programEntry("drive_c/Game.exe", in: bottleURL)))
    }

    @Test("A Steam launch is matched by App ID in any bottle, as the routing store is keyed")
    func steamMatching() {
        let launch = RecordedLaunch(bottleURL: bottleURL, target: .steam(appID: 440), date: .now)

        #expect(launch.isLaunch(of: steamEntry(440, in: bottleURL)))
        #expect(launch.isLaunch(of: steamEntry(440, in: otherBottleURL)))
        #expect(!launch.isLaunch(of: steamEntry(550, in: bottleURL)))
        #expect(!launch.isLaunch(of: programEntry("drive_c/hl2.exe", in: bottleURL)))
    }

    @Test("A launch moves a never-run or older date forward and leaves anything else alone")
    func lastPlayed() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3_600)
        let later = now.addingTimeInterval(60)
        let entry = programEntry("drive_c/Game.exe", in: bottleURL)
        let launch = RecordedLaunch(bottleURL: bottleURL, target: .program(name: "Game.exe"), date: now)

        #expect(launch.lastPlayed(nil, for: entry) == now)
        #expect(launch.lastPlayed(earlier, for: entry) == now)
        #expect(launch.lastPlayed(later, for: entry) == later)

        let unrelated = programEntry("drive_c/Other.exe", in: bottleURL)
        #expect(launch.lastPlayed(nil, for: unrelated) == nil)
        #expect(launch.lastPlayed(earlier, for: unrelated) == earlier)
    }

    @Test("The notification carries the launch, and other notifications carry none")
    @MainActor
    func notificationRoundTrip() {
        let center = NotificationCenter()
        let launch = RecordedLaunch(bottleURL: bottleURL, target: .steam(appID: 440), date: .now)
        let recorder = LaunchRecorder()
        let observer = center.addObserver(forName: RecordedLaunch.didRecordNotification, object: nil, queue: nil) {
            if let launch = RecordedLaunch(notification: $0) {
                recorder.append(launch)
            }
        }
        defer { center.removeObserver(observer) }

        launch.post(to: center)

        #expect(recorder.launches == [launch])
        #expect(RecordedLaunch(notification: Notification(name: .init("other"), userInfo: [
            RecordedLaunch.userInfoKey: launch
        ])) == nil)
    }

    @Test("Recording a program's run start announces it with the run's start time")
    @MainActor
    func runStartPosts() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "whisky-recorded-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bottle = Bottle(bottleUrl: folder, isAvailable: true)

        // Only this bottle's: a launch elsewhere in the suite may announce its own.
        let recorder = LaunchRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: RecordedLaunch.didRecordNotification, object: nil, queue: nil
        ) {
            if let launch = RecordedLaunch(notification: $0), launch.bottleURL == folder {
                recorder.append(launch)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = Wine.recordRunStart(
            programName: "Game.exe", logFileURL: folder.appending(path: "run.log"),
            launch: Wine.PreparedLaunch(environment: [:], arguments: []), programSettings: nil, bottle: bottle
        )

        // Posted synchronously, before the launch goes on to start the program.
        let launch = try #require(recorder.launches.first)
        #expect(recorder.launches.count == 1)
        #expect(launch.target == .program(name: "Game.exe"))
        // The run log stores its dates to a coarser precision than they are made with.
        let started = try #require(RunLogStore.load(for: "Game.exe", in: folder).entries.last?.startTime)
        #expect(abs(launch.date.timeIntervalSince(started)) < 1)
    }
}
