//
//  RockstarD3DStatus.swift
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

/// What the bottle settings say about the Rockstar Games Launcher's Wine
/// Direct3D while GPTK is deployed (#382).
public enum RockstarWineD3DStatus: Equatable, Sendable {
    /// `system32` holds Wine's `d3d11`, and Steam and Social Club keep DXVK.
    case active
    /// The next launch of Steam or the launcher from Whisky puts it in place.
    case pending
    /// The user turned it off.
    case off
    /// The last launch that decided could not put it in place, and why.
    case notApplied(RockstarD3DLayout.Reason)
}

public extension Bottle {
    /// The Rockstar Games Launcher's Wine Direct3D status for the settings,
    /// or `nil` when the bottle has nothing to show: no Rockstar launcher with
    /// GPTK deployed, and no swap on record.
    ///
    /// Cheap enough for a view body: a few `stat` calls and the layout the
    /// last launch decided (``rockstarD3DLayout``), never a library scan.
    /// After the app restarts no launch has decided yet, so a bottle with a
    /// record reads as active and one without as pending, until the next
    /// launch of Steam or the launcher resolves it.
    var rockstarWineD3DStatus: RockstarWineD3DStatus? {
        rockstarWineD3DStatus(payloadDeployed: GPTKImporter.isDeployed())
    }

    /// ``rockstarWineD3DStatus`` with the GPTK payload's state given.
    internal func rockstarWineD3DStatus(payloadDeployed: Bool) -> RockstarWineD3DStatus? {
        let recordExists = RockstarD3DLayoutRecord.exists(in: url)
        guard recordExists || (payloadDeployed && Wine.rockstarInstalled(bottleURL: url)) else { return nil }
        guard settings.rockstarWineD3D else { return .off }
        switch rockstarD3DLayout {
        case .swapped:
            return .active
        case .builtin:
            return nil
        case let .degraded(reason) where reason != .disabledByUser && reason != .gptkForwarders:
            return .notApplied(reason)
        case .degraded, nil:
            return recordExists ? .active : .pending
        }
    }
}
