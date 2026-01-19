//
//  EnumsAndDataModelsTests.swift
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

// MARK: - Magic Enum Tests

final class MagicEnumTests: XCTestCase {
    func testMagicRawValues() {
        XCTAssertEqual(PEFile.Magic.unknown.rawValue, 0x0)
        XCTAssertEqual(PEFile.Magic.pe32.rawValue, 0x10B)
        XCTAssertEqual(PEFile.Magic.pe32Plus.rawValue, 0x20B)
    }

    func testMagicInitFromRawValue() {
        XCTAssertEqual(PEFile.Magic(rawValue: 0x0), .unknown)
        XCTAssertEqual(PEFile.Magic(rawValue: 0x10B), .pe32)
        XCTAssertEqual(PEFile.Magic(rawValue: 0x20B), .pe32Plus)
    }

    func testMagicInitFromInvalidRawValue() {
        XCTAssertNil(PEFile.Magic(rawValue: 0x1))
        XCTAssertNil(PEFile.Magic(rawValue: 0x100))
        XCTAssertNil(PEFile.Magic(rawValue: 0xFFFF))
    }

    func testMagicDescription() {
        XCTAssertEqual(PEFile.Magic.unknown.description, "unknown")
        XCTAssertEqual(PEFile.Magic.pe32.description, "PE32")
        XCTAssertEqual(PEFile.Magic.pe32Plus.description, "PE32+")
    }

    func testMagicHashable() {
        var set = Set<PEFile.Magic>()
        set.insert(.unknown)
        set.insert(.pe32)
        set.insert(.pe32Plus)

        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(.unknown))
        XCTAssertTrue(set.contains(.pe32))
        XCTAssertTrue(set.contains(.pe32Plus))
    }

    func testMagicEquatable() {
        XCTAssertEqual(PEFile.Magic.pe32, PEFile.Magic.pe32)
        XCTAssertNotEqual(PEFile.Magic.pe32, PEFile.Magic.pe32Plus)
        XCTAssertNotEqual(PEFile.Magic.unknown, PEFile.Magic.pe32)
    }
}

// MARK: - Architecture Enum Tests

final class ArchitectureEnumTests: XCTestCase {
    func testArchitectureToString() {
        XCTAssertEqual(Architecture.x32.toString(), "32-bit")
        XCTAssertEqual(Architecture.x64.toString(), "64-bit")
        XCTAssertNil(Architecture.unknown.toString())
    }

    func testArchitectureHashable() {
        var set = Set<Architecture>()
        set.insert(.x32)
        set.insert(.x64)
        set.insert(.unknown)

        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(.x32))
        XCTAssertTrue(set.contains(.x64))
        XCTAssertTrue(set.contains(.unknown))
    }

    func testArchitectureEquatable() {
        XCTAssertEqual(Architecture.x32, Architecture.x32)
        XCTAssertEqual(Architecture.x64, Architecture.x64)
        XCTAssertNotEqual(Architecture.x32, Architecture.x64)
        XCTAssertNotEqual(Architecture.x32, Architecture.unknown)
    }
}

// MARK: - Locales Enum Tests

final class LocalesEnumTests: XCTestCase {
    func testLocalesRawValues() {
        XCTAssertEqual(Locales.auto.rawValue, "")
        XCTAssertEqual(Locales.german.rawValue, "de_DE.UTF-8")
        XCTAssertEqual(Locales.english.rawValue, "en_US.UTF-8")
        XCTAssertEqual(Locales.spanish.rawValue, "es_ES.UTF-8")
        XCTAssertEqual(Locales.french.rawValue, "fr_FR.UTF-8")
        XCTAssertEqual(Locales.italian.rawValue, "it_IT.UTF-8")
        XCTAssertEqual(Locales.japanese.rawValue, "ja_JP.UTF-8")
        XCTAssertEqual(Locales.korean.rawValue, "ko_KR.UTF-8")
        XCTAssertEqual(Locales.russian.rawValue, "ru_RU.UTF-8")
        XCTAssertEqual(Locales.ukranian.rawValue, "uk_UA.UTF-8")
        XCTAssertEqual(Locales.thai.rawValue, "th_TH.UTF-8")
        XCTAssertEqual(Locales.chineseSimplified.rawValue, "zh_CN.UTF-8")
        XCTAssertEqual(Locales.chineseTraditional.rawValue, "zh_TW.UTF-8")
    }

    func testLocalesUkrainianAlias() {
        XCTAssertEqual(Locales.ukrainian, Locales.ukranian)
        XCTAssertEqual(Locales.ukrainian.rawValue, "uk_UA.UTF-8")
    }

    func testLocalesPrettyDisplayNames() {
        XCTAssertEqual(Locales.german.pretty(), "Deutsch")
        XCTAssertEqual(Locales.english.pretty(), "English")
        XCTAssertEqual(Locales.spanish.pretty(), "Español")
        XCTAssertEqual(Locales.french.pretty(), "Français")
        XCTAssertEqual(Locales.italian.pretty(), "Italiano")
        XCTAssertEqual(Locales.japanese.pretty(), "日本語")
        XCTAssertEqual(Locales.korean.pretty(), "한국어")
        XCTAssertEqual(Locales.russian.pretty(), "Русский")
        XCTAssertEqual(Locales.ukranian.pretty(), "Українська")
        XCTAssertEqual(Locales.thai.pretty(), "ไทย")
        XCTAssertEqual(Locales.chineseSimplified.pretty(), "简体中文")
        XCTAssertEqual(Locales.chineseTraditional.pretty(), "繁體中文")
    }

    func testLocalesCaseIterable() {
        let allCases = Locales.allCases
        XCTAssertEqual(allCases.count, 13)
        XCTAssertTrue(allCases.contains(.auto))
        XCTAssertTrue(allCases.contains(.english))
        XCTAssertTrue(allCases.contains(.japanese))
    }

    func testLocalesCodable() throws {
        // PropertyListEncoder cannot encode a raw string as a top-level value,
        // so we wrap it in a container struct for the round-trip test
        struct LocaleContainer: Codable {
            let locale: Locales
        }

        for locale in Locales.allCases {
            let container = LocaleContainer(locale: locale)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(container)

            let decoded = try PropertyListDecoder().decode(LocaleContainer.self, from: data)
            XCTAssertEqual(decoded.locale, locale, "Round-trip should preserve locale \(locale)")
        }
    }
}

// MARK: - ProgramSettings Tests

final class ProgramSettingsTests: XCTestCase {
    func testDefaultInitialization() {
        let settings = ProgramSettings()

        XCTAssertEqual(settings.locale, .auto)
        XCTAssertEqual(settings.environment, [:])
        XCTAssertEqual(settings.arguments, "")
    }

    func testSettingsWithCustomValues() {
        var settings = ProgramSettings()
        settings.locale = .japanese
        settings.arguments = "-windowed -nosound"
        settings.environment["WINEDEBUG"] = "-all"
        settings.environment["CUSTOM_VAR"] = "value"

        XCTAssertEqual(settings.locale, .japanese)
        XCTAssertEqual(settings.arguments, "-windowed -nosound")
        XCTAssertEqual(settings.environment.count, 2)
        XCTAssertEqual(settings.environment["WINEDEBUG"], "-all")
        XCTAssertEqual(settings.environment["CUSTOM_VAR"], "value")
    }

    func testSettingsRoundTripEncoding() throws {
        var original = ProgramSettings()
        original.locale = .korean
        original.arguments = "--debug --verbose"
        original.environment["TEST_KEY"] = "test_value"

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)

        XCTAssertEqual(decoded.locale, original.locale)
        XCTAssertEqual(decoded.arguments, original.arguments)
        XCTAssertEqual(decoded.environment, original.environment)
    }

    func testSettingsEncodeDecodeWithTempFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let settingsURL = tempDir.appending(path: "test_settings_\(UUID().uuidString).plist")

        defer {
            try? FileManager.default.removeItem(at: settingsURL)
        }

        var original = ProgramSettings()
        original.locale = .french
        original.arguments = "-fullscreen"
        original.environment["DEBUG"] = "1"

        try original.encode(to: settingsURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)))

        let decoded = try ProgramSettings.decode(from: settingsURL)

        XCTAssertEqual(decoded.locale, original.locale)
        XCTAssertEqual(decoded.arguments, original.arguments)
        XCTAssertEqual(decoded.environment, original.environment)
    }

    func testSettingsDecodeCreatesDefaultIfMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let nonExistentURL = tempDir.appending(path: "non_existent_\(UUID().uuidString).plist")

        defer {
            try? FileManager.default.removeItem(at: nonExistentURL)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistentURL.path(percentEncoded: false)))

        let settings = try ProgramSettings.decode(from: nonExistentURL)

        XCTAssertEqual(settings.locale, .auto)
        XCTAssertEqual(settings.environment, [:])
        XCTAssertEqual(settings.arguments, "")

        XCTAssertTrue(FileManager.default.fileExists(atPath: nonExistentURL.path(percentEncoded: false)))
    }

    func testSettingsWithAllLocales() throws {
        for locale in Locales.allCases {
            var settings = ProgramSettings()
            settings.locale = locale

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(settings)

            let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)
            XCTAssertEqual(decoded.locale, locale, "Round-trip should preserve locale \(locale)")
        }
    }

    func testSettingsWithEmptyEnvironment() throws {
        var settings = ProgramSettings()
        settings.environment = [:]

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(settings)

        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)
        XCTAssertEqual(decoded.environment, [:])
    }

    func testSettingsWithLargeEnvironment() throws {
        var settings = ProgramSettings()
        for index in 0 ..< 50 {
            settings.environment["KEY_\(index)"] = "VALUE_\(index)"
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(settings)

        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)
        XCTAssertEqual(decoded.environment.count, 50)
        XCTAssertEqual(decoded.environment["KEY_25"], "VALUE_25")
    }
}

// MARK: - PEError Tests

final class PEErrorTests: XCTestCase {
    func testInvalidPEFileError() {
        let error = PEError.invalidPEFile
        XCTAssertEqual(error.message, "Invalid PE file")
    }

    func testPEErrorIsError() {
        let error = PEError.invalidPEFile
        XCTAssertTrue(error is Error)
    }

    func testPEErrorEquality() {
        let error1 = PEError(message: "Test error")
        let error2 = PEError(message: "Test error")
        let error3 = PEError(message: "Different error")

        XCTAssertEqual(error1.message, error2.message)
        XCTAssertNotEqual(error1.message, error3.message)
    }
}
