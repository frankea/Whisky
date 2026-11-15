//
//  GPTKImporterSerializationTests.swift
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

@Suite("GPTK importer serialization")
struct GPTKImporterSerializationTests {
    private func makeStore() throws -> URL {
        let store = FileManager.default.temporaryDirectory
            .appending(path: "GPTKImporterSerializationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try Data("record".utf8).write(to: store.appending(path: "D3DMetalVersion.plist"))
        return store
    }

    @Test("Removing the store deletes it, and a missing store is not an error")
    func removeStoreDeletesAndToleratesMissing() throws {
        let store = try makeStore()
        try GPTKImporter.removeStore(at: store)
        #expect(!FileManager.default.fileExists(atPath: store.path(percentEncoded: false)))
        try GPTKImporter.removeStore(at: store)
    }

    @Test("A store write waits while another one holds the lock")
    func storeWritesAreSerialized() throws {
        let store = try makeStore()
        let path = store.path(percentEncoded: false)
        let done = DispatchSemaphore(value: 0)
        // A recursive lock is owned by the thread that took it, so this thread
        // both holds and releases it while another thread tries to write.
        GPTKImporter.mutationLock.lock()
        DispatchQueue.global().async {
            try? GPTKImporter.removeStore(at: store)
            done.signal()
        }
        let finishedWhileHeld = done.wait(timeout: .now() + .milliseconds(300)) == .success
        let existedWhileHeld = FileManager.default.fileExists(atPath: path)
        GPTKImporter.mutationLock.unlock()
        #expect(!finishedWhileHeld)
        #expect(existedWhileHeld)
        #expect(done.wait(timeout: .now() + .seconds(10)) == .success)
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
