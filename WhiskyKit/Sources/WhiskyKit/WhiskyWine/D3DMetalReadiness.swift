//
//  D3DMetalReadiness.swift
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

/// Whether the D3DMetal backend can be used, and if not, which of its two
/// requirements is missing.
///
/// D3DMetal needs Apple's Game Porting Toolkit payload, which the user
/// imports in Settings, and an engine build that can run it, which only a
/// GPTK-capable Whisky engine is (``WhiskyWineVersion/gptkCapable``). The two
/// are independent: importing the payload into the stock engine succeeds but
/// never deploys it, so the app has to say which half is missing rather than
/// blaming the payload for what the engine lacks (#358).
public enum D3DMetalReadiness: Equatable, Sendable, CaseIterable {
    /// D3DMetal is in the runtime and can be selected.
    case available
    /// The installed engine can run D3DMetal, but no usable payload is
    /// imported.
    case payloadMissing
    /// The payload is imported, but the installed engine cannot run it.
    case engineNotCapable
    /// No payload is imported and the installed engine cannot run one.
    case payloadAndEngineMissing

    /// Decides readiness from what is on disk.
    ///
    /// - Parameters:
    ///   - payloadImported: an imported payload is in the store
    ///     (``GPTKImporter/storedRecord()`` is not `nil`).
    ///   - engineCapable: the installed engine advertises `gptkCapable`
    ///     (``GPTKImporter/isRuntimeGPTKCapable()``).
    ///   - payloadInRuntime: the payload is in the runtime tree
    ///     (``WhiskyWineInstaller/isD3DMetalInstalled()``), the same input
    ///     ``WhiskyWineInstaller/isBackendAvailable(_:)`` reads, so this is
    ///     ``available`` exactly when that call says D3DMetal can be selected.
    ///
    /// A payload in the runtime counts as available whatever the other two
    /// say, as backend availability already treats it: one copied in by hand
    /// has no store record. An imported payload on a capable engine that is
    /// still not in the runtime failed the checks its deploy applies (Settings
    /// reports why), and importing it again is the fix, so that reads as
    /// ``payloadMissing``.
    public init(payloadImported: Bool, engineCapable: Bool, payloadInRuntime: Bool) {
        if payloadInRuntime {
            self = .available
        } else if engineCapable {
            self = .payloadMissing
        } else {
            self = payloadImported ? .engineNotCapable : .payloadAndEngineMissing
        }
    }

    /// Readiness of the installed runtime and the imported payload.
    public static func current() -> D3DMetalReadiness {
        current(store: GPTKImporter.storeFolder, libraryFolder: WhiskyWineInstaller.libraryFolder)
    }

    /// Testable seam for ``current()``.
    static func current(store: URL, libraryFolder: URL) -> D3DMetalReadiness {
        D3DMetalReadiness(
            payloadImported: GPTKImporter.storedRecord(inStore: store) != nil,
            engineCapable: GPTKImporter.isRuntimeGPTKCapable(inLibraryFolder: libraryFolder),
            payloadInRuntime: WhiskyWineInstaller.isD3DMetalPresent(inLibraryFolder: libraryFolder)
        )
    }

    /// Whether D3DMetal can be selected.
    public var isAvailable: Bool {
        self == .available
    }

    /// Whether a GPTK-capable engine is among what is missing, so the user
    /// should be pointed at the engine releases.
    public var needsCapableEngine: Bool {
        self == .engineNotCapable || self == .payloadAndEngineMissing
    }

    /// Whether importing the payload is among what is missing.
    public var needsPayload: Bool {
        self == .payloadMissing || self == .payloadAndEngineMissing
    }

    /// Where the GPTK-capable engines are published: beta Wine Libraries
    /// releases, installed by hand until one is promoted to the stock engine.
    public static let engineReleasesURL = URL(string: DistributionConfig.releasesPageURL)
}
