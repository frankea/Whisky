//
//  VirtualDesktopResolutionTests.swift
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

final class VirtualDesktopResolutionTests: XCTestCase {
    private let retinaDisplay: () -> (width: Int, height: Int)? = { (width: 3_024, height: 1_964) }
    private let noDisplay: () -> (width: Int, height: Int)? = { nil }

    // MARK: - ResolutionPreset.resolutionString

    func testFixedPresetsUseTheirOwnSize() {
        for preset in ResolutionPreset.allCases {
            guard let dims = preset.dimensions else { continue }
            XCTAssertEqual(
                preset.resolutionString(customWidth: 800, customHeight: 600, displaySize: retinaDisplay),
                "\(dims.width)x\(dims.height)"
            )
        }
    }

    func testMatchDisplayUsesTheDisplaySize() {
        XCTAssertEqual(
            ResolutionPreset.matchDisplay.resolutionString(
                customWidth: 800, customHeight: 600, displaySize: retinaDisplay
            ),
            "3024x1964"
        )
    }

    func testMatchDisplayFallsBackWhenTheDisplayCannotBeRead() {
        XCTAssertEqual(
            ResolutionPreset.matchDisplay.resolutionString(customWidth: 800, customHeight: 600, displaySize: noDisplay),
            "1920x1080"
        )
    }

    func testCustomUsesTheCustomSize() {
        XCTAssertEqual(
            ResolutionPreset.custom.resolutionString(customWidth: 2_048, customHeight: 1_152, displaySize: noDisplay),
            "2048x1152"
        )
    }

    func testFixedPresetsNeverReadTheDisplay() {
        var reads = 0
        let counting: () -> (width: Int, height: Int)? = {
            reads += 1
            return nil
        }
        _ = ResolutionPreset.r2560x1440.resolutionString(customWidth: 1, customHeight: 1, displaySize: counting)
        _ = ResolutionPreset.custom.resolutionString(customWidth: 1, customHeight: 1, displaySize: counting)
        XCTAssertEqual(reads, 0)
    }

    // MARK: - Per-program virtual desktop

    func testProgramMatchDisplayUsesTheDisplayNotFullHD() {
        var overrides = ProgramOverrides()
        overrides.virtualDesktopEnabled = true
        overrides.resolutionPreset = .matchDisplay
        XCTAssertEqual(Wine.resolveVirtualDesktopResolution(from: overrides, displaySize: retinaDisplay), "3024x1964")
    }

    func testProgramMatchDisplayFallsBackLikeTheBottleSection() {
        var overrides = ProgramOverrides()
        overrides.resolutionPreset = .matchDisplay
        XCTAssertEqual(Wine.resolveVirtualDesktopResolution(from: overrides, displaySize: noDisplay), "1920x1080")
    }

    func testProgramWithoutPresetDefaultsToFullHD() {
        XCTAssertEqual(
            Wine.resolveVirtualDesktopResolution(from: ProgramOverrides(), displaySize: retinaDisplay),
            "1920x1080"
        )
    }

    func testProgramCustomSizeUsesItsOverrideOrTheDefault() {
        var overrides = ProgramOverrides()
        overrides.resolutionPreset = .custom
        overrides.customResolutionWidth = 1_280
        XCTAssertEqual(Wine.resolveVirtualDesktopResolution(from: overrides, displaySize: noDisplay), "1280x1080")
        overrides.customResolutionHeight = 800
        XCTAssertEqual(Wine.resolveVirtualDesktopResolution(from: overrides, displaySize: noDisplay), "1280x800")
    }

    func testProgramAndBottleResolveMatchDisplayTheSameWay() {
        var overrides = ProgramOverrides()
        overrides.resolutionPreset = .matchDisplay
        let bottleSide = ResolutionPreset.matchDisplay.resolutionString(
            customWidth: 1_920, customHeight: 1_080, displaySize: retinaDisplay
        )
        XCTAssertEqual(Wine.resolveVirtualDesktopResolution(from: overrides, displaySize: retinaDisplay), bottleSide)
    }
}
