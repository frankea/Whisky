//
//  WhiskyUITests.swift
//  WhiskyUITests
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

import XCTest

final class WhiskyUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-WhiskyUITestMode", "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// Smoke: app launches and the four bottle-detail navigation rows render.
    /// Doesn't depend on sidebar visibility (it persists collapsed/expanded state
    /// between launches). Assumes at least one bottle exists in the user container.
    func testAppLaunchesAndShowsBottleDetail() throws {
        let configRow = app.buttons["nav.bottleConfiguration"]
        XCTAssertTrue(configRow.waitForExistence(timeout: 8),
                      "Bottle Configuration row did not appear within 8s of launch")
        XCTAssertTrue(app.buttons["nav.installedPrograms"].exists)
        XCTAssertTrue(app.buttons["nav.runningProcesses"].exists)
        XCTAssertTrue(app.buttons["nav.gameConfigurations"].exists)
    }

    /// Regression: no UI element should ever render a raw localization key.
    /// This catches the whole class of bugs found during manual smoke testing
    /// (e.g. `config.title.graphics` rendering raw, `bottle.subtitle.autoBackend`
    /// missing the `%@` in its xcstrings key).
    func testNoRawLocalizationKeysVisible() throws {
        XCTAssertTrue(app.buttons["nav.bottleConfiguration"].waitForExistence(timeout: 8))
        app.buttons["nav.bottleConfiguration"].click()

        // Wait for Bottle Configuration to load - the Wine section is its first row
        _ = app.staticTexts["Wine"].waitForExistence(timeout: 5)

        // Walk every visible static text. None should look like a raw dotted key.
        // (Heuristic: contains ".", no whitespace, starts lowercase.)
        let suspicious = app.staticTexts.allElementsBoundByIndex.compactMap { element -> String? in
            let label = element.label
            guard !label.isEmpty,
                  label.contains("."),
                  !label.contains(" "),
                  let first = label.first, first.isLowercase
            else { return nil }
            return label
        }
        XCTAssertTrue(suspicious.isEmpty,
                      "Unlocalized strings rendered raw: \(suspicious)")
    }
}
