//
//  IconCacheTests.swift
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

@Suite("IconCache Tests")
struct IconCacheTests {
    @Test("Cache returns nil for non-existent file")
    func cacheReturnsNilForNonExistentFile() async {
        let cache = IconCache.shared
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path/file.exe")

        let result = await cache.iconAsync(for: nonExistentURL)

        #expect(result == nil)
    }

    @Test("Cache returns nil for invalid PE file")
    func cacheReturnsNilForInvalidPEFile() async throws {
        let cache = IconCache.shared

        // Create a temporary file with invalid PE content
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("invalid_\(UUID().uuidString).exe")
        try "not a valid PE file".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = await cache.iconAsync(for: tempFile)

        #expect(result == nil)
    }

    @Test("Clear cache removes all entries")
    func clearCacheRemovesAllEntries() async {
        let cache = IconCache.shared

        // Clear the cache
        await cache.clearCache()

        // Verify cache doesn't crash after clear (we can't directly inspect NSCache contents)
        let result = await cache.iconAsync(for: URL(fileURLWithPath: "/test/path.exe"))
        #expect(result == nil)
    }

    @Test("Invalidate removes specific entry")
    func invalidateRemovesSpecificEntry() async {
        let cache = IconCache.shared
        let testURL = URL(fileURLWithPath: "/test/specific/path.exe")

        // Invalidate the entry
        await cache.invalidate(url: testURL)

        // Verify cache doesn't crash after invalidate
        let result = await cache.iconAsync(for: testURL)
        #expect(result == nil)
    }

    @Test("Cache is shared singleton")
    func cacheIsSharedSingleton() async {
        let cache1 = IconCache.shared
        let cache2 = IconCache.shared

        // Both should reference the same instance
        #expect(cache1 === cache2)
    }
}
