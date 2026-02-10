// swiftlint:disable file_length
//
//  GameDBEntry.swift
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

// MARK: - Supporting Types

/// A fingerprint for identifying a specific executable version.
///
/// Combines optional SHA-256 hash, file size, and PE timestamp to match
/// against known game executables. At least one field should be non-nil
/// for a meaningful fingerprint.
public struct ExeFingerprint: Codable, Sendable, Equatable {
    /// The SHA-256 hash of the executable file, if computed.
    public let sha256: String?
    /// The file size in bytes.
    public let fileSize: Int64?
    /// The PE COFF header timestamp.
    public let peTimestamp: Date?

    public init(sha256: String? = nil, fileSize: Int64? = nil, peTimestamp: Date? = nil) {
        self.sha256 = sha256
        self.fileSize = fileSize
        self.peTimestamp = peTimestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        self.peTimestamp = try container.decodeIfPresent(Date.self, forKey: .peTimestamp)
    }
}

/// Hardware and software constraints for a game configuration.
///
/// Used both for filtering applicable entries and for auto-selecting
/// the best variant for the current machine.
public struct GameConstraints: Codable, Sendable, Equatable {
    /// Supported CPU architectures (e.g., ["arm64", "x86_64"]).
    public let cpuArchitectures: [String]?
    /// Minimum macOS version required (e.g., "15.0.0").
    public let minMacOSVersion: String?
    /// Minimum Wine version required (e.g., "9.0").
    public let minWineVersion: String?
    /// Backend capabilities required (e.g., ["dxr"]).
    public let requiredBackendCapabilities: [String]?

    public init(
        cpuArchitectures: [String]? = nil,
        minMacOSVersion: String? = nil,
        minWineVersion: String? = nil,
        requiredBackendCapabilities: [String]? = nil
    ) {
        self.cpuArchitectures = cpuArchitectures
        self.minMacOSVersion = minMacOSVersion
        self.minWineVersion = minWineVersion
        self.requiredBackendCapabilities = requiredBackendCapabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cpuArchitectures = try container.decodeIfPresent([String].self, forKey: .cpuArchitectures)
        self.minMacOSVersion = try container.decodeIfPresent(String.self, forKey: .minMacOSVersion)
        self.minWineVersion = try container.decodeIfPresent(String.self, forKey: .minWineVersion)
        self.requiredBackendCapabilities = try container.decodeIfPresent(
            [String].self,
            forKey: .requiredBackendCapabilities
        )
    }
}

/// Information about the environment used to test a game configuration.
///
/// Enables staleness detection by comparing against the user's current setup.
public struct TestedWith: Codable, Sendable, Equatable {
    /// When the configuration was last tested.
    public let lastTestedAt: Date
    /// The macOS version used during testing.
    public let macOSVersion: String
    /// The Wine version used during testing.
    public let wineVersion: String
    /// The Whisky version used during testing, if known.
    public let whiskyVersion: String?
    /// The CPU architecture used during testing (e.g., "arm64").
    public let cpuArchitecture: String?

    public init(
        lastTestedAt: Date,
        macOSVersion: String,
        wineVersion: String,
        whiskyVersion: String? = nil,
        cpuArchitecture: String? = nil
    ) {
        self.lastTestedAt = lastTestedAt
        self.macOSVersion = macOSVersion
        self.wineVersion = wineVersion
        self.whiskyVersion = whiskyVersion
        self.cpuArchitecture = cpuArchitecture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lastTestedAt = try container.decode(Date.self, forKey: .lastTestedAt)
        self.macOSVersion = try container.decode(String.self, forKey: .macOSVersion)
        self.wineVersion = try container.decode(String.self, forKey: .wineVersion)
        self.whiskyVersion = try container.decodeIfPresent(String.self, forKey: .whiskyVersion)
        self.cpuArchitecture = try container.decodeIfPresent(String.self, forKey: .cpuArchitecture)
    }
}

/// A known issue with a game, displayed in the detail view.
public struct KnownIssue: Codable, Sendable, Equatable {
    /// A description of the issue.
    public let description: String
    /// The severity level (e.g., "minor", "major", "critical").
    public let severity: String?
    /// A workaround for the issue, if known.
    public let workaround: String?

    public init(description: String, severity: String? = nil, workaround: String? = nil) {
        self.description = description
        self.severity = severity
        self.workaround = workaround
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.description = try container.decode(String.self, forKey: .description)
        self.severity = try container.decodeIfPresent(String.self, forKey: .severity)
        self.workaround = try container.decodeIfPresent(String.self, forKey: .workaround)
    }
}

/// Metadata about who created and last updated a game database entry.
public struct Provenance: Codable, Sendable, Equatable {
    /// The source of the configuration (e.g., "maintainer-verified", "community").
    public let source: String
    /// The author of the configuration.
    public let author: String?
    /// When the entry was last updated.
    public let lastUpdated: Date?
    /// A URL to the source reference (e.g., GitHub issue, wiki page).
    public let referenceURL: URL?

    public init(source: String, author: String? = nil, lastUpdated: Date? = nil, referenceURL: URL? = nil) {
        self.source = source
        self.author = author
        self.lastUpdated = lastUpdated
        self.referenceURL = referenceURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decode(String.self, forKey: .source)
        self.author = try container.decodeIfPresent(String.self, forKey: .author)
        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        self.referenceURL = try container.decodeIfPresent(URL.self, forKey: .referenceURL)
    }
}

// MARK: - Variant Settings

/// Settings values within a game configuration variant.
///
/// Each property maps directly to a ``BottleSettings`` property name,
/// allowing the applicator to set values without a translation layer.
/// All fields are optional; `nil` means "do not change this setting."
public struct GameConfigVariantSettings: Codable, Sendable, Equatable {
    /// The graphics backend to use.
    public let graphicsBackend: GraphicsBackend?
    /// Whether DXVK should be enabled.
    public let dxvk: Bool?
    /// Whether DXVK async shader compilation should be enabled.
    public let dxvkAsync: Bool?
    /// The enhanced sync mode.
    public let enhancedSync: EnhancedSync?
    /// Whether to force D3D11 mode.
    public let forceD3D11: Bool?
    /// The performance preset name.
    public let performancePreset: String?
    /// Whether shader caching should be enabled.
    public let shaderCacheEnabled: Bool?
    /// Whether AVX instruction set support should be advertised.
    public let avxEnabled: Bool?
    /// Whether macOS Sequoia compatibility mode should be enabled.
    public let sequoiaCompatMode: Bool?

    public init(
        graphicsBackend: GraphicsBackend? = nil,
        dxvk: Bool? = nil,
        dxvkAsync: Bool? = nil,
        enhancedSync: EnhancedSync? = nil,
        forceD3D11: Bool? = nil,
        performancePreset: String? = nil,
        shaderCacheEnabled: Bool? = nil,
        avxEnabled: Bool? = nil,
        sequoiaCompatMode: Bool? = nil
    ) {
        self.graphicsBackend = graphicsBackend
        self.dxvk = dxvk
        self.dxvkAsync = dxvkAsync
        self.enhancedSync = enhancedSync
        self.forceD3D11 = forceD3D11
        self.performancePreset = performancePreset
        self.shaderCacheEnabled = shaderCacheEnabled
        self.avxEnabled = avxEnabled
        self.sequoiaCompatMode = sequoiaCompatMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.graphicsBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend)
        self.dxvk = try container.decodeIfPresent(Bool.self, forKey: .dxvk)
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync)
        // EnhancedSync uses Swift's auto-synthesized Codable (keyed enum, not String raw value).
        // The JSON database uses plain strings ("none", "esync", "msync") for readability,
        // so we try String first and fall back to the native Codable format.
        if let syncString = try container.decodeIfPresent(String.self, forKey: .enhancedSync) {
            switch syncString {
            case "none": self.enhancedSync = .none
            case "esync": self.enhancedSync = .esync
            case "msync": self.enhancedSync = .msync
            default: self.enhancedSync = nil
            }
        } else {
            self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync)
        }
        self.forceD3D11 = try container.decodeIfPresent(Bool.self, forKey: .forceD3D11)
        self.performancePreset = try container.decodeIfPresent(String.self, forKey: .performancePreset)
        self.shaderCacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .shaderCacheEnabled)
        self.avxEnabled = try container.decodeIfPresent(Bool.self, forKey: .avxEnabled)
        self.sequoiaCompatMode = try container.decodeIfPresent(Bool.self, forKey: .sequoiaCompatMode)
    }
}

// MARK: - Game Config Variant

/// A specific configuration variant for a game.
///
/// A single game entry can have multiple variants (e.g., "Apple Silicon",
/// "Intel", "DXVK mode"). Each variant contains the full set of settings
/// to apply, along with metadata about when and why to use it.
public struct GameConfigVariant: Codable, Sendable, Equatable {
    /// Stable identifier for this variant.
    public let id: String
    /// A human-readable label (e.g., "Recommended (Apple Silicon)").
    public let label: String
    /// Whether this is the default variant. The first variant with
    /// `isDefault == true` is auto-selected; if none, the first variant is used.
    public let isDefault: Bool?
    /// A description of when this variant should be used.
    public let whenToUse: String?
    /// Explanation of why these settings are recommended.
    public let rationale: [String]?
    /// The settings to apply for this variant.
    public let settings: GameConfigVariantSettings
    /// Additional environment variables to set (not covered by named settings).
    public let environmentVariables: [String: String]?
    /// DLL overrides to add when applying this variant.
    public let dllOverrides: [DLLOverrideEntry]?
    /// Winetricks verbs required by this variant.
    public let winetricksVerbs: [String]?
    /// Information about when and how this variant was tested.
    public let testedWith: TestedWith?

    public init(
        id: String,
        label: String,
        isDefault: Bool? = nil,
        whenToUse: String? = nil,
        rationale: [String]? = nil,
        settings: GameConfigVariantSettings,
        environmentVariables: [String: String]? = nil,
        dllOverrides: [DLLOverrideEntry]? = nil,
        winetricksVerbs: [String]? = nil,
        testedWith: TestedWith? = nil
    ) {
        self.id = id
        self.label = label
        self.isDefault = isDefault
        self.whenToUse = whenToUse
        self.rationale = rationale
        self.settings = settings
        self.environmentVariables = environmentVariables
        self.dllOverrides = dllOverrides
        self.winetricksVerbs = winetricksVerbs
        self.testedWith = testedWith
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.label = try container.decode(String.self, forKey: .label)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        self.whenToUse = try container.decodeIfPresent(String.self, forKey: .whenToUse)
        self.rationale = try container.decodeIfPresent([String].self, forKey: .rationale)
        self.settings = try container.decodeIfPresent(
            GameConfigVariantSettings.self,
            forKey: .settings
        ) ?? GameConfigVariantSettings()
        self.environmentVariables = try container.decodeIfPresent(
            [String: String].self,
            forKey: .environmentVariables
        )
        self.dllOverrides = try container.decodeIfPresent([DLLOverrideEntry].self, forKey: .dllOverrides)
        self.winetricksVerbs = try container.decodeIfPresent([String].self, forKey: .winetricksVerbs)
        self.testedWith = try container.decodeIfPresent(TestedWith.self, forKey: .testedWith)
    }
}

// MARK: - Game Database Entry

/// A single entry in the game compatibility database.
///
/// Each entry describes a game, its compatibility rating, matching
/// identifiers (Steam App ID, exe names, fingerprints), and one or
/// more configuration variants with recommended settings.
///
/// ## Example JSON
///
/// ```json
/// {
///   "id": "elden-ring",
///   "title": "Elden Ring",
///   "rating": "playable",
///   "variants": [{ "id": "recommended", "label": "Recommended", "settings": {} }]
/// }
/// ```
public struct GameDBEntry: Codable, Sendable, Equatable {
    /// Stable identifier for this entry.
    public let id: String
    /// The display title of the game.
    public let title: String
    /// Alternative names for search matching.
    public let aliases: [String]?
    /// A subtitle (e.g., edition or publisher).
    public let subtitle: String?
    /// The store this game is associated with (e.g., "steam", "gog").
    public let store: String?
    /// The Steam App ID, if the game is on Steam.
    public let steamAppId: Int?
    /// The compatibility rating for this game.
    public let rating: CompatibilityRating
    /// Known executable filenames for matching.
    public let exeNames: [String]?
    /// Executable fingerprints for hard-identifier matching.
    public let exeFingerprints: [ExeFingerprint]?
    /// Path patterns for heuristic matching (e.g., "elden ring/game").
    public let pathPatterns: [String]?
    /// Anti-cheat system name, if applicable.
    public let antiCheat: String?
    /// Hardware and software constraints.
    public let constraints: GameConstraints?
    /// Configuration variants (at least one required).
    public let variants: [GameConfigVariant]
    /// General notes displayed in the detail view.
    public let notes: [String]?
    /// Known issues with workarounds.
    public let knownIssues: [KnownIssue]?
    /// Provenance metadata (source, author, last updated).
    public let provenance: Provenance?

    /// The default configuration variant for this entry.
    ///
    /// Returns the first variant where ``GameConfigVariant/isDefault`` is `true`.
    /// If no variant is marked as default, returns the first variant.
    /// Returns `nil` only if the variants array is empty.
    public var defaultVariant: GameConfigVariant? {
        variants.first { $0.isDefault == true } ?? variants.first
    }

    public init(
        id: String,
        title: String,
        aliases: [String]? = nil,
        subtitle: String? = nil,
        store: String? = nil,
        steamAppId: Int? = nil,
        rating: CompatibilityRating,
        exeNames: [String]? = nil,
        exeFingerprints: [ExeFingerprint]? = nil,
        pathPatterns: [String]? = nil,
        antiCheat: String? = nil,
        constraints: GameConstraints? = nil,
        variants: [GameConfigVariant],
        notes: [String]? = nil,
        knownIssues: [KnownIssue]? = nil,
        provenance: Provenance? = nil
    ) {
        self.id = id
        self.title = title
        self.aliases = aliases
        self.subtitle = subtitle
        self.store = store
        self.steamAppId = steamAppId
        self.rating = rating
        self.exeNames = exeNames
        self.exeFingerprints = exeFingerprints
        self.pathPatterns = pathPatterns
        self.antiCheat = antiCheat
        self.constraints = constraints
        self.variants = variants
        self.notes = notes
        self.knownIssues = knownIssues
        self.provenance = provenance
    }

    // swiftlint:disable function_body_length
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.aliases = try container.decodeIfPresent([String].self, forKey: .aliases)
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        self.store = try container.decodeIfPresent(String.self, forKey: .store)
        self.steamAppId = try container.decodeIfPresent(Int.self, forKey: .steamAppId)
        self.rating = try container.decodeIfPresent(
            CompatibilityRating.self,
            forKey: .rating
        ) ?? .unverified
        self.exeNames = try container.decodeIfPresent([String].self, forKey: .exeNames)
        self.exeFingerprints = try container.decodeIfPresent([ExeFingerprint].self, forKey: .exeFingerprints)
        self.pathPatterns = try container.decodeIfPresent([String].self, forKey: .pathPatterns)
        self.antiCheat = try container.decodeIfPresent(String.self, forKey: .antiCheat)
        self.constraints = try container.decodeIfPresent(GameConstraints.self, forKey: .constraints)
        self.variants = try container.decodeIfPresent([GameConfigVariant].self, forKey: .variants) ?? []
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes)
        self.knownIssues = try container.decodeIfPresent([KnownIssue].self, forKey: .knownIssues)
        self.provenance = try container.decodeIfPresent(Provenance.self, forKey: .provenance)
    }
    // swiftlint:enable function_body_length
}

// swiftlint:enable file_length
