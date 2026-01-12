//
//  ProgramSettings.swift
//  WhiskyKit
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

/// Available locale settings for Windows programs.
///
/// Setting a locale can help programs display text correctly, especially
/// for games that require specific language settings for proper character
/// rendering or localized content.
///
/// ## Example
///
/// ```swift
/// program.settings.locale = .japanese
/// ```
public enum Locales: String, Codable, CaseIterable, Sendable {
    /// Automatic locale detection (uses system default).
    case auto = ""
    /// German (Germany) locale.
    case german = "de_DE.UTF-8"
    /// English (United States) locale.
    case english = "en_US"
    /// Spanish (Spain) locale.
    case spanish = "es_ES.UTF-8"
    /// French (France) locale.
    case french = "fr_FR.UTF-8"
    /// Italian (Italy) locale.
    case italian = "it_IT.UTF-8"
    /// Japanese (Japan) locale.
    case japanese = "ja_JP.UTF-8"
    /// Korean (Korea) locale.
    case korean = "ko_KR.UTF-8"
    /// Russian (Russia) locale.
    case russian = "ru_RU.UTF-8"
    /// Ukrainian (Ukraine) locale.
    ///
    /// - Note: The enum case name `ukranian` is intentionally misspelled
    ///   for backward compatibility with existing settings files. The raw
    ///   value `"uk_UA.UTF-8"` is correct and is the intended locale identifier.
    ///   Use ``ukrainian`` for the correctly-spelled version.
    case ukranian = "uk_UA.UTF-8"
    /// Thai (Thailand) locale.
    case thai = "th_TH.UTF-8"
    /// Simplified Chinese (China) locale.
    case chineseSimplified = "zh_CN.UTF-8"
    /// Traditional Chinese (Taiwan) locale.
    case chineseTraditional = "zh_TW.UTF-8"

    /// Ukrainian (Ukraine) locale with correct spelling.
    ///
    /// This is an alias for ``ukranian`` (misspelled) which is kept for
    /// backward compatibility with existing settings files. New code should
    /// prefer this correctly-spelled version.
    public static let ukrainian: Locales = .ukranian

    /// Returns a human-readable display name for the locale.
    ///
    /// The display name is shown in the locale's native script when available.
    /// For example, Japanese returns "日本語" rather than "Japanese".
    ///
    /// - Returns: The localized display name for this locale.
    public func pretty() -> String { // swiftlint:disable:this cyclomatic_complexity
        switch self {
        case .auto:
            String(localized: "locale.auto")
        case .german:
            "Deutsch"
        case .english:
            "English"
        case .spanish:
            "Español"
        case .french:
            "Français"
        case .italian:
            "Italiano"
        case .japanese:
            "日本語"
        case .korean:
            "한국어"
        case .russian:
            "Русский"
        case .ukranian:
            "Українська"
        case .thai:
            "ไทย"
        case .chineseSimplified:
            "简体中文"
        case .chineseTraditional:
            "繁體中文"
        }
    }
}

/// Configuration settings for an individual Windows program.
///
/// Program settings allow per-program customization that can override
/// bottle-level defaults. These settings are stored in a separate plist
/// file for each program.
///
/// ## Example
///
/// ```swift
/// var settings = ProgramSettings()
/// settings.locale = .japanese
/// settings.arguments = "-windowed -nosound"
/// settings.environment["WINEDEBUG"] = "-all"
/// ```
public struct ProgramSettings: Codable {
    /// The locale to use when running this program.
    ///
    /// Setting a specific locale can help with character encoding
    /// and localized content in games.
    public var locale: Locales = .auto
    /// Custom environment variables for this program.
    ///
    /// These variables are added to the Wine environment when the
    /// program is executed. They can be used to enable debugging,
    /// configure Wine behavior, or pass application-specific settings.
    public var environment: [String: String] = [:]
    /// Command-line arguments to pass to the program.
    ///
    /// Arguments are appended after the executable path when the
    /// program is launched through Wine.
    public var arguments: String = ""

    /// Loads program settings from a plist file.
    ///
    /// If the file doesn't exist, default settings are created and saved.
    ///
    /// - Parameter settingsURL: The URL to the settings plist file.
    /// - Returns: The decoded settings or new default settings.
    /// - Throws: An error if the file exists but cannot be decoded.
    static func decode(from settingsURL: URL) throws -> ProgramSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)) else {
            let settings = ProgramSettings()
            try settings.encode(to: settingsURL)
            return settings
        }

        let data = try Data(contentsOf: settingsURL)
        return try PropertyListDecoder().decode(ProgramSettings.self, from: data)
    }

    /// Saves the settings to a plist file.
    ///
    /// - Parameter settingsURL: The URL where settings should be saved.
    /// - Throws: An error if the settings cannot be encoded or written.
    func encode(to settingsURL: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: settingsURL)
    }
}
