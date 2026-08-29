//
//  WineUserProfileTests.swift
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

@Suite("Wine user profile reconcile")
struct WineUserProfileTests {
    private let fileManager = FileManager.default
    private let unixName = "tester"

    /// A throwaway prefix with a `drive_c/users` directory and nothing else.
    private func makePrefix() throws -> URL {
        let prefix = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(
            at: prefix.appending(path: "drive_c/users/Public"), withIntermediateDirectories: true
        )
        return prefix
    }

    private func users(_ prefix: URL) -> URL {
        prefix.appending(path: "drive_c/users")
    }

    /// Lays down what wineboot creates for a fresh profile: directories only.
    private func makeSkeleton(_ dir: URL) throws {
        for sub in ["Desktop", "Documents", "AppData/Local/Temp", "AppData/Roaming"] {
            try fileManager.createDirectory(at: dir.appending(path: sub), withIntermediateDirectories: true)
        }
    }

    /// A profile that has been used: the skeleton plus a file an app wrote.
    private func makePopulated(_ dir: URL) throws {
        try makeSkeleton(dir)
        try Data("marker".utf8).write(to: dir.appending(path: "AppData/Roaming/marker.txt"))
    }

    private func symlinkTarget(_ url: URL) -> String? {
        try? fileManager.destinationOfSymbolicLink(atPath: url.path)
    }

    private func reconcile(_ prefix: URL) -> WineUserProfile.Outcome {
        WineUserProfile.reconcile(bottleURL: prefix, unixUserName: unixName)
    }

    @Test("A stock-lineage profile gets a crossover alias")
    func aliasesUnixProfileForCrossOver() throws {
        let prefix = try makePrefix()
        try makePopulated(users(prefix).appending(path: unixName))

        #expect(reconcile(prefix) == .linked(name: "crossover", target: unixName))
        #expect(symlinkTarget(users(prefix).appending(path: "crossover")) == unixName)
        let viaAlias = users(prefix).appending(path: "crossover/AppData/Roaming/marker.txt")
        #expect(fileManager.fileExists(atPath: viaAlias.path))
    }

    @Test("A crossover-lineage profile gets a unix-name alias")
    func aliasesCrossOverProfileForUnixName() throws {
        let prefix = try makePrefix()
        try makePopulated(users(prefix).appending(path: "crossover"))

        #expect(reconcile(prefix) == .linked(name: unixName, target: "crossover"))
        #expect(symlinkTarget(users(prefix).appending(path: unixName)) == "crossover")
    }

    @Test("An empty skeleton beside a populated profile is moved aside and aliased")
    func replacesEmptySkeleton() throws {
        let prefix = try makePrefix()
        try makePopulated(users(prefix).appending(path: unixName))
        try makeSkeleton(users(prefix).appending(path: "crossover"))

        let outcome = reconcile(prefix)
        guard case let .replacedSkeleton(name, target, movedTo) = outcome else {
            Issue.record("expected replacedSkeleton, got \(outcome)")
            return
        }
        #expect(name == "crossover")
        #expect(target == unixName)
        #expect(fileManager.fileExists(atPath: movedTo.path))
        #expect(symlinkTarget(users(prefix).appending(path: "crossover")) == unixName)
    }

    @Test("Temp files do not make a skeleton count as populated")
    func tempFilesAreNotUserData() throws {
        let prefix = try makePrefix()
        try makePopulated(users(prefix).appending(path: unixName))
        let skeleton = users(prefix).appending(path: "crossover")
        try makeSkeleton(skeleton)
        try Data("scratch".utf8).write(to: skeleton.appending(path: "AppData/Local/Temp/scratch.tmp"))

        guard case .replacedSkeleton = reconcile(prefix) else {
            Issue.record("a skeleton with only Temp contents should be replaced")
            return
        }
    }

    @Test("Two populated profiles are left alone")
    func leavesTwoPopulatedProfiles() throws {
        let prefix = try makePrefix()
        try makePopulated(users(prefix).appending(path: unixName))
        try makePopulated(users(prefix).appending(path: "crossover"))

        #expect(reconcile(prefix) == .bothPopulated)
        #expect(symlinkTarget(users(prefix).appending(path: "crossover")) == nil)
        #expect(symlinkTarget(users(prefix).appending(path: unixName)) == nil)
    }

    @Test("Reconciling twice is a no-op the second time")
    func isIdempotent() throws {
        let prefix = try makePrefix()
        try makePopulated(users(prefix).appending(path: unixName))

        _ = reconcile(prefix)
        #expect(reconcile(prefix) == .alreadyConsistent)
        #expect(symlinkTarget(users(prefix).appending(path: "crossover")) == unixName)
    }

    @Test("A hand-made alias is respected even if it points elsewhere")
    func respectsExistingSymlink() throws {
        let prefix = try makePrefix()
        try makePopulated(users(prefix).appending(path: "someone-else"))
        try fileManager.createSymbolicLink(
            atPath: users(prefix).appending(path: "crossover").path, withDestinationPath: "someone-else"
        )

        #expect(reconcile(prefix) == .alreadyConsistent)
        #expect(symlinkTarget(users(prefix).appending(path: "crossover")) == "someone-else")
    }

    @Test("A prefix that has not been booted is untouched")
    func skipsUnbootedPrefix() throws {
        let prefix = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: prefix, withIntermediateDirectories: true)

        #expect(reconcile(prefix) == .nothingToReconcile)
    }

    @Test("A users directory with only Public is untouched")
    func skipsPrefixWithoutProfiles() throws {
        let prefix = try makePrefix()

        #expect(reconcile(prefix) == .nothingToReconcile)
        #expect(!fileManager.fileExists(atPath: users(prefix).appending(path: "crossover").path))
    }
}
