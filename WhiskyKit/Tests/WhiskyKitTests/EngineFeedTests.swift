//
//  EngineFeedTests.swift
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
import SemanticVersion
import Testing
@testable import WhiskyKit

@Suite("Engine update feeds")
struct EngineFeedTests {
    /// Apps before 3.10.0 keep reading the old feed, which stays on the stock
    /// engine. This app must read a different one, or a bump meant for it
    /// would reach them too.
    @Test("The app reads the 4.x feed, not the frozen one older apps read")
    func readsTheVersionedFeed() {
        #expect(DistributionConfig.versionPlistURL != DistributionConfig.legacyVersionPlistURL)
        #expect(DistributionConfig.legacyVersionPlistURL == "https://frankea.github.io/Whisky/WhiskyWineVersion.plist")
    }

    /// The published feeds decode as the app reads them: the old one still on
    /// 3.1.1, the new one on a GPTK-capable 4.x engine with a digest.
    @Test("The published feeds name the engines each app line should get")
    func publishedFeedsDecode() throws {
        let pages = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "dist/pages")
        let decoder = PropertyListDecoder()
        let legacy = try decoder.decode(
            WhiskyWineVersion.self, from: Data(contentsOf: pages.appending(path: "WhiskyWineVersion.plist"))
        )
        let current = try decoder.decode(
            WhiskyWineVersion.self, from: Data(contentsOf: pages.appending(path: "WhiskyWineVersion-v4.plist"))
        )
        #expect(legacy.version == SemanticVersion(3, 1, 1))
        #expect(current.version.major == 4)
        #expect(current.gptkCapable == true)
        #expect(current.sha256?.count == 64)
    }
}
