//
//  EnvironmentBuilderTests.swift
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

@testable import WhiskyKit
import XCTest

final class EnvironmentBuilderTests: XCTestCase {
    // MARK: - Layer Resolution

    func testEmptyBuilderResolvesToEmptyEnvironment() {
        let builder = EnvironmentBuilder()
        let result = builder.resolve()
        XCTAssertTrue(result.environment.isEmpty)
        XCTAssertTrue(result.provenance.entries.isEmpty)
    }

    func testLaterLayerWinsForSameKey() {
        var builder = EnvironmentBuilder()
        builder.set("KEY", "a", layer: .base)
        builder.set("KEY", "b", layer: .platform)
        let result = builder.resolve()
        XCTAssertEqual(result.environment["KEY"], "b")
    }

    func testMultipleKeysAcrossLayers() {
        var builder = EnvironmentBuilder()
        builder.set("A", "1", layer: .base)
        builder.set("B", "2", layer: .platform)
        let result = builder.resolve()
        XCTAssertEqual(result.environment["A"], "1")
        XCTAssertEqual(result.environment["B"], "2")
    }

    func testRemoveKeyFromLayer() {
        var builder = EnvironmentBuilder()
        builder.set("KEY", "val", layer: .base)
        builder.remove("KEY", layer: .bottleManaged)
        let result = builder.resolve()
        XCTAssertNil(result.environment["KEY"])
    }

    func testSetAllSetsMultipleKeys() {
        var builder = EnvironmentBuilder()
        builder.setAll(["X": "1", "Y": "2"], layer: .bottleUser)
        let result = builder.resolve()
        XCTAssertEqual(result.environment["X"], "1")
        XCTAssertEqual(result.environment["Y"], "2")
    }

    // MARK: - Provenance Tracking

    func testProvenanceTracksWinningLayer() {
        var builder = EnvironmentBuilder()
        builder.set("KEY", "a", layer: .base)
        builder.set("KEY", "b", layer: .platform)
        let result = builder.resolve()
        XCTAssertEqual(result.provenance.entries["KEY"]?.layer, .platform)
    }

    func testProvenanceTracksOverriddenBy() {
        var builder = EnvironmentBuilder()
        builder.set("KEY", "a", layer: .base)
        builder.set("KEY", "b", layer: .platform)
        let result = builder.resolve()
        // The base entry was overridden by platform
        // The winning entry should have overriddenBy == nil (it won)
        XCTAssertNil(result.provenance.entries["KEY"]?.overriddenBy)
        XCTAssertEqual(result.provenance.entries["KEY"]?.layer, .platform)
    }

    func testProvenanceActiveLayers() {
        var builder = EnvironmentBuilder()
        builder.set("A", "1", layer: .base)
        builder.set("B", "2", layer: .programUser)
        let result = builder.resolve()
        XCTAssertTrue(result.provenance.activeLayers.contains(.base))
        XCTAssertTrue(result.provenance.activeLayers.contains(.programUser))
        XCTAssertFalse(result.provenance.activeLayers.contains(.platform))
    }
}
