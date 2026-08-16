//
//  BottleDiscordConfig.swift
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

/// Whether a bottle talks to the Discord client, and how.
///
/// Both are off by default. What a person is playing is not Whisky's to
/// announce unless they ask for it, and neither switch is worth turning on for
/// someone who does not use Discord.
public struct BottleDiscordConfig: Codable, Equatable {
    /// Whisky publishes the program it launched, as itself.
    var presence: Bool = false

    /// Games in this bottle may publish their own rich presence.
    var bridge: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.presence = (try? container.decodeIfPresent(Bool.self, forKey: .presence)) ?? false
        self.bridge = (try? container.decodeIfPresent(Bool.self, forKey: .bridge)) ?? false
    }
}
