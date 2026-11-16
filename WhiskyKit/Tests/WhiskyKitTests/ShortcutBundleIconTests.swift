//
//  ShortcutBundleIconTests.swift
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

import AppKit
import Foundation
import ImageIO
@testable import WhiskyKit
import XCTest

final class ShortcutBundleIconTests: XCTestCase {
    private var tempDir: URL!
    private var appURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "ShortcutIcon-\(UUID().uuidString)")
        appURL = tempDir.appending(path: "Game.app")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private var iconURL: URL {
        appURL.appending(path: "Contents/Resources/AppIcon.icns")
    }

    private func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: appURL.appending(path: "Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    /// A solid 32 by 32 bitmap, like a small PE icon.
    private func makeIcon() throws -> NSImage {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        for column in 0 ..< 32 {
            for row in 0 ..< 32 {
                rep.setColor(.systemOrange, atX: column, y: row)
            }
        }
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    func testInfoPlistNamesTheAppAndItsType() throws {
        let data = try ShortcutCreator.infoPlist(name: "Rock & Roll <Deluxe>")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["CFBundleName"] as? String, "Rock & Roll <Deluxe>")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "launch")
        XCTAssertNil(plist["CFBundleIconFile"])

        let withIcon = try ShortcutCreator.infoPlist(name: "Game", iconFileName: "AppIcon")
        let iconPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: withIcon, format: nil) as? [String: Any]
        )
        XCTAssertEqual(iconPlist["CFBundleIconFile"] as? String, "AppIcon")
    }

    func testBundleEmbedsTheIconAsICNS() throws {
        let written = try ShortcutCreator.createShortcutBundle(
            at: appURL,
            launchScript: "echo hi",
            name: "Game",
            icon: makeIcon()
        )

        XCTAssertTrue(written)
        XCTAssertEqual(try infoPlist()["CFBundleIconFile"] as? String, ShortcutCreator.iconFileName)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(iconURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "com.apple.icns")
        XCTAssertGreaterThan(CGImageSourceGetCount(source), 0)
    }

    func testBundleWithoutIconHasNoIconEntry() throws {
        let written = try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: "echo hi", name: "Game")

        XCTAssertFalse(written)
        XCTAssertNil(try infoPlist()["CFBundleIconFile"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: iconURL.path(percentEncoded: false)))
    }

    func testReplacingABundleDropsWhatTheOldOneHeld() throws {
        try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: "echo old", name: "Game", icon: makeIcon())
        // What a Finder custom icon leaves behind inside the bundle.
        let customIcon = appURL.appending(path: "Icon\r")
        try Data().write(to: customIcon)

        try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: "echo new", name: "Game")

        XCTAssertFalse(FileManager.default.fileExists(atPath: customIcon.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: iconURL.path(percentEncoded: false)))
        let script = try String(contentsOf: appURL.appending(path: "Contents/MacOS/launch"), encoding: .utf8)
        XCTAssertTrue(script.hasSuffix("echo new"))
    }

    func testOnlyAShortcutCountsAsOneToReplaceInPlace() throws {
        try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: "echo hi", name: "Game")
        XCTAssertTrue(ShortcutCreator.isShortcutBundle(at: appURL))

        // A real app with the same name, which goes to the Trash instead.
        let realApp = tempDir.appending(path: "Steam.app")
        let macos = realApp.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try Data().write(to: macos.appending(path: "steam_osx"))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": "steam_osx"],
            format: .xml,
            options: 0
        )
        try plist.write(to: realApp.appending(path: "Contents/Info.plist"))
        XCTAssertFalse(ShortcutCreator.isShortcutBundle(at: realApp))

        // Even with a file named like the script, the executable must be it.
        try Data().write(to: macos.appending(path: "launch"))
        XCTAssertFalse(ShortcutCreator.isShortcutBundle(at: realApp))
        XCTAssertFalse(ShortcutCreator.isShortcutBundle(at: tempDir.appending(path: "Missing.app")))
    }
}
