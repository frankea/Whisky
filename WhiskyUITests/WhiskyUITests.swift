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

// swiftlint:disable type_body_length
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

    // MARK: - Helpers

    /// Wait up to `timeout` for an element, returning it on success or failing the test on miss.
    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Required element missing: \(description)",
            file: file,
            line: line
        )
        return element
    }

    /// Walk every visible static text label and return any that look like raw localization keys.
    /// Heuristic: contains a `.`, no whitespace, starts lowercase.
    private func rawKeyLeaks() -> [String] {
        app.staticTexts.allElementsBoundByIndex.compactMap { element -> String? in
            let label = element.label
            guard !label.isEmpty,
                  label.contains("."),
                  !label.contains(" "),
                  let first = label.first, first.isLowercase
            else { return nil }
            return label
        }
    }

    /// Navigate to Bottle Configuration view of the currently-selected bottle.
    private func openBottleConfiguration() {
        let configRow = require(
            app.buttons["nav.bottleConfiguration"],
            "bottle nav row",
            timeout: 8
        )
        configRow.click()
        require(
            app.staticTexts["Wine"],
            "Wine section header in Bottle Configuration",
            timeout: 5
        )
    }

    /// Navigate to Game Configurations view of the currently-selected bottle.
    /// Waits for the list to populate (GameDBLoader runs in `.onAppear`).
    private func openGameConfigurations() {
        let row = require(
            app.buttons["nav.gameConfigurations"],
            "game configs nav row",
            timeout: 8
        )
        row.click()
        let list = require(app.outlines["gamedb.list"], "GameDB list outline", timeout: 5)
        // Wait for the outline to actually have rows - the loader runs in onAppear so
        // there is a brief gap between the outline appearing and rows materializing.
        let firstRow = list.outlineRows.firstMatch
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 5),
            "GameDB list rendered but no rows materialized within 5s"
        )
    }

    // MARK: - Smoke

    /// Throws XCTSkip if the user container has no bottles. CI runners start fresh
    /// without fixtures, and most of these tests assume at least one bottle exists.
    private func requireBottleFixture() throws {
        if !app.buttons["nav.bottleConfiguration"].waitForExistence(timeout: 5) {
            throw XCTSkip(
                "No bottle fixtures in user container; skipping. " +
                    "Run a bottle setup locally before running this suite."
            )
        }
    }

    func testAppLaunchesAndShowsBottleDetail() throws {
        try requireBottleFixture()
        require(app.buttons["nav.bottleConfiguration"], "bottle nav row", timeout: 8)
        XCTAssertTrue(app.buttons["nav.installedPrograms"].exists)
        XCTAssertTrue(app.buttons["nav.runningProcesses"].exists)
        XCTAssertTrue(app.buttons["nav.gameConfigurations"].exists)
    }

    func testBottomToolbarShowsAllFourActions() throws {
        try requireBottleFixture()
        // BottomBarButtonStyle wraps each button in a new Button, which strips our
        // accessibility identifiers. Look up by visible label instead.
        XCTAssertTrue(app.buttons["Open C: Drive"].exists, "Open C: Drive button missing")
        XCTAssertTrue(app.buttons["Terminal..."].exists, "Terminal button missing")
        XCTAssertTrue(app.buttons["Winetricks..."].exists, "Winetricks button missing")
        XCTAssertTrue(app.buttons["Run..."].exists, "Run button missing")
    }

    func testCreateBottleButtonPresentInToolbar() throws {
        try requireBottleFixture()
        XCTAssertTrue(
            app.buttons.matching(identifier: "toolbar.createBottle").firstMatch.exists,
            "+ toolbar button missing"
        )
    }

    // MARK: - Bottle Configuration

    func testBottleConfigurationSectionsRender() throws {
        try requireBottleFixture()
        openBottleConfiguration()
        // Wine section is the first one expanded by default
        XCTAssertTrue(app.staticTexts["Wine"].exists)
        // Other section headers should be reachable as collapsible groups (collapsed by default)
        XCTAssertTrue(
            app.staticTexts["Launcher Compatibility"].exists ||
                app.staticTexts["Controller & Input"].exists,
            "Expected at least one collapsible config section header"
        )
    }

    /// Verifies the Controller & Input section exists as a collapsed DisclosureGroup
    /// in Bottle Configuration. The Cmd→Ctrl toggle inside it is verified by source
    /// inspection - SwiftUI doesn't expose collapsed DisclosureGroup contents in
    /// the AX tree, so we can't drive the toggle via XCUITest without expanding it,
    /// which itself requires clicking the chevron at a fragile coordinate.
    func testControllerAndInputSectionExists() throws {
        try requireBottleFixture()
        openBottleConfiguration()
        // The header renders as a DisclosureTriangle with label "Controller & Input",
        // not as a StaticText. Disclosure triangles report as descendant of a window.
        let predicate = NSPredicate(format: "label CONTAINS 'Controller'")
        let disclosure = app.descendants(matching: .disclosureTriangle).matching(predicate)
            .firstMatch
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 5),
            "Controller & Input section header missing"
        )
    }

    // MARK: - Game Configurations browser

    func testGameDBBrowserShowsEntries() throws {
        try requireBottleFixture()
        openGameConfigurations()
        // We bundle 80+ entries; assert at least one row renders.
        let firstRow = app.outlines["gamedb.list"].outlineRows.firstMatch
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 5),
            "GameDB browser is empty - bundled entries failed to load"
        )
    }

    /// Open the Celeste GameDB detail view. We use a deterministic row id rather
    /// than walking outline rows because OutlineRow descendants aren't reliably
    /// hittable on macOS - the actual click target is the inner Button.
    private func openCelesteDetail() {
        let row = require(
            app.buttons["gamedb.row.celeste"],
            "Celeste row button",
            timeout: 5
        )
        row.click()
    }

    func testGameDBSearchFiltersEntries() throws {
        try requireBottleFixture()
        openGameConfigurations()
        let searchField: XCUIElement = {
            if app.searchFields.firstMatch.exists { return app.searchFields.firstMatch }
            return app.textFields.firstMatch
        }()
        require(searchField, "GameDB search field", timeout: 5)
        searchField.click()
        searchField.typeText("celeste")
        // The Celeste row should still be present after filtering;
        // most other rows should be filtered out.
        XCTAssertTrue(
            app.buttons["gamedb.row.celeste"].waitForExistence(timeout: 5),
            "Search for 'celeste' did not surface the Celeste row"
        )
        XCTAssertFalse(
            app.buttons["gamedb.row.aoe2-de"].exists,
            "Search filter should hide unrelated entries"
        )
    }

    func testGameDBDetailViewRendersForCeleste() throws {
        try requireBottleFixture()
        openGameConfigurations()
        openCelesteDetail()
        require(
            app.buttons["gamedb.detail.applyButton"],
            "Apply button on detail view",
            timeout: 5
        )
    }

    func testApplyConfigPreviewSheetCancels() throws {
        try requireBottleFixture()
        openGameConfigurations()
        openCelesteDetail()

        let applyButton = require(
            app.buttons["gamedb.detail.applyButton"],
            "Apply button",
            timeout: 5
        )
        applyButton.click()

        let cancelButton = require(
            app.buttons["gamedb.preview.cancelButton"],
            "preview Cancel button",
            timeout: 5
        )
        XCTAssertTrue(
            app.buttons["gamedb.preview.applyButton"].exists,
            "preview Apply Configuration button missing"
        )
        cancelButton.click()

        // Sheet should dismiss
        XCTAssertFalse(
            app.buttons["gamedb.preview.cancelButton"].waitForExistence(timeout: 2),
            "Preview sheet failed to dismiss after Cancel"
        )
    }

    // MARK: - Localization regression

    /// Bottle Configuration view should not leak any raw localization keys.
    /// This is the highest-leverage test - catches the entire class of regressions
    /// that manual smoke testing kept finding (config.title.graphics, status.duplicating.*,
    /// bottle.subtitle.autoBackend, etc.).
    func testNoRawKeysInBottleConfiguration() throws {
        try requireBottleFixture()
        openBottleConfiguration()
        let leaks = rawKeyLeaks()
        XCTAssertTrue(
            leaks.isEmpty,
            "Bottle Configuration leaked raw localization keys: \(leaks)"
        )
    }

    /// Same check, but for the GameDB browser.
    func testNoRawKeysInGameConfigurations() throws {
        try requireBottleFixture()
        openGameConfigurations()
        let leaks = rawKeyLeaks()
        XCTAssertTrue(
            leaks.isEmpty,
            "Game Configurations leaked raw localization keys: \(leaks)"
        )
    }

    /// Same check, but for the GameDB detail view.
    func testNoRawKeysInGameDetail() throws {
        try requireBottleFixture()
        openGameConfigurations()
        openCelesteDetail()
        require(app.buttons["gamedb.detail.applyButton"], "detail view loaded", timeout: 5)
        let leaks = rawKeyLeaks()
        XCTAssertTrue(
            leaks.isEmpty,
            "GameDB detail view leaked raw localization keys: \(leaks)"
        )
    }

    /// Same check, but for the apply-config preview sheet (the overlay where the diff
    /// shows). Verifies sheet content is fully localized.
    func testNoRawKeysInApplyPreviewSheet() throws {
        try requireBottleFixture()
        openGameConfigurations()
        openCelesteDetail()
        require(app.buttons["gamedb.detail.applyButton"], "detail view", timeout: 5).click()
        require(app.buttons["gamedb.preview.cancelButton"], "preview sheet", timeout: 5)

        let leaks = rawKeyLeaks()
        XCTAssertTrue(
            leaks.isEmpty,
            "Apply preview sheet leaked raw localization keys: \(leaks)"
        )

        app.buttons["gamedb.preview.cancelButton"].click()
    }

    // MARK: - Create-bottle sheet

    func testCreateBottleSheetOpensAndCancels() {
        // macOS toolbar buttons render as paired wrapper+inner buttons sharing the
        // same identifier. Click the first match, which is the hittable wrapper.
        let createButton = require(
            app.buttons.matching(identifier: "toolbar.createBottle").firstMatch,
            "+ toolbar button", timeout: 5
        )
        createButton.click()

        // Sheet should expose the name field and Cancel/Create buttons
        let nameField = require(
            app.textFields["create.nameField"],
            "create-bottle name field",
            timeout: 3
        )
        XCTAssertTrue(app.buttons["create.cancelButton"].exists, "Cancel button missing")
        // Create button should start disabled (empty name)
        XCTAssertFalse(
            app.buttons["create.createButton"].isEnabled,
            "Create button should be disabled when name is empty"
        )
        // Type a name and verify Create becomes enabled
        nameField.click()
        nameField.typeText("UITestBottle")
        XCTAssertTrue(
            app.buttons["create.createButton"].isEnabled,
            "Create button should enable once name is non-empty"
        )
        // Don't actually create - cancel out
        app.buttons["create.cancelButton"].click()

        // Sheet should dismiss
        XCTAssertFalse(
            app.textFields["create.nameField"]
                .waitForExistence(timeout: 1),
            "Create sheet failed to dismiss after Cancel"
        )
    }
}

// swiftlint:enable type_body_length
