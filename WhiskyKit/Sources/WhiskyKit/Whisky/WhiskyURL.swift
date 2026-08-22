//
//  WhiskyURL.swift
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

/// What a `whisky://` URL is allowed to say.
///
/// This parser is the security boundary of the URL scheme, which is why it
/// lives apart from the code that acts on it and is tested on its own. There
/// are exactly two forms and no third:
///
/// ```
/// whisky://launch?steam=<appid>[&bottle=<name>]
/// whisky://launch?pin=<name>[&bottle=<name>]
/// ```
///
/// Neither can name an executable. A `path=` form would let any web page pick
/// the program, so the guarantee is the absence of one: a URL can only reach
/// state the user created, an app ID installed in a bottle they have or a pin
/// they made by hand. The allowlist is the shape of this type rather than a
/// list anyone maintains, and it stops being true the moment a form is added
/// that takes a path or resolves against anything else.
///
/// Parsing does not decide whether the target exists. That is
/// `QuickLaunch`'s job, and it happens before the user is asked to confirm, so
/// the confirmation can name what will actually run.
public enum WhiskyURL {
    /// A well-formed request. `bottle` narrows the search when the same app ID
    /// or pin name exists in more than one bottle.
    public enum Request: Equatable, Sendable {
        case steam(appId: Int, bottle: String?)
        case pin(name: String, bottle: String?)
    }

    public static let scheme = "whisky"

    /// Parses a URL, or returns `nil` for anything that is not one of the two
    /// forms, including a different scheme, a different host, a missing or
    /// non-numeric app ID, an empty pin name, and any unknown parameter.
    ///
    /// - Parameter url: The URL to parse.
    /// - Returns: The request, or `nil` if the URL says anything else.
    public static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "launch",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let items = components.queryItems ?? []
        // an unknown parameter means a form this build does not know, which must
        // not silently degrade into the half of it that parses
        guard items.allSatisfy({ ["steam", "pin", "bottle"].contains($0.name) }) else { return nil }

        let bottle = items.first { $0.name == "bottle" }?.value.flatMap { $0.isEmpty ? nil : $0 }
        let steam = items.first { $0.name == "steam" }?.value
        let pin = items.first { $0.name == "pin" }?.value

        // guessing which of the two was meant is how a launcher starts the
        // wrong thing
        switch (steam, pin) {
        case let (steam?, nil):
            guard let appId = Int(steam), appId > 0 else { return nil }
            return .steam(appId: appId, bottle: bottle)
        case let (nil, pin?):
            guard !pin.isEmpty else { return nil }
            return .pin(name: pin, bottle: bottle)
        default:
            return nil
        }
    }
}
