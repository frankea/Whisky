//
//  WhiskyWineUpdateCheckSettingTests.swift
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

final class WhiskyWineUpdateCheckSettingTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "WhiskyWineUpdateCheckSettingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToEnabledWhenNeverSet() {
        XCTAssertTrue(WhiskyWineInstaller.automaticUpdateChecksEnabled(in: defaults))
    }

    func testTurningTheSettingOffDisablesTheAutomaticCheck() {
        defaults.set(false, forKey: WhiskyWineInstaller.automaticUpdateCheckDefaultsKey)
        XCTAssertFalse(WhiskyWineInstaller.automaticUpdateChecksEnabled(in: defaults))
    }

    func testTurningTheSettingBackOnEnablesTheAutomaticCheck() {
        defaults.set(false, forKey: WhiskyWineInstaller.automaticUpdateCheckDefaultsKey)
        defaults.set(true, forKey: WhiskyWineInstaller.automaticUpdateCheckDefaultsKey)
        XCTAssertTrue(WhiskyWineInstaller.automaticUpdateChecksEnabled(in: defaults))
    }

    func testKeyMatchesTheSettingsToggle() {
        // SettingsView stores the toggle under this key; renaming it would
        // silently reset every user's choice.
        XCTAssertEqual(WhiskyWineInstaller.automaticUpdateCheckDefaultsKey, "checkWhiskyWineUpdates")
    }
}
