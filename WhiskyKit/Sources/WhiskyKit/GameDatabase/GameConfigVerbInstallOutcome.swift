//
//  GameConfigVerbInstallOutcome.swift
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

/// Where the winetricks components of an applied game configuration ended up.
///
/// Applying a configuration installs the verbs its variant needs that the
/// bottle lacks, one at a time. Each verb is recorded as installed or failed
/// as its install finishes; a verb never recorded (the user left components
/// out, or cancelled before it ran) counts as not installed. Only a run where
/// every requested verb installed is ``Status/complete``, so the result never
/// reads as a success while something the configuration needs is missing.
public struct GameConfigVerbInstallOutcome: Sendable, Equatable {
    /// How the components of an apply turned out.
    public enum Status: Sendable, Equatable {
        /// Every requested verb installed (or none were needed).
        case complete
        /// At least one verb was attempted and failed.
        case failed
        /// Nothing failed, but some verbs were never installed.
        case incomplete
    }

    /// The verbs the apply needed, in install order.
    public let requested: [String]
    /// The verbs whose install succeeded.
    public private(set) var installed: [String] = []
    /// The verbs whose install was attempted and failed.
    public private(set) var failed: [String] = []

    public init(requested: [String]) {
        var seen: Set<String> = []
        self.requested = requested.filter { seen.insert($0).inserted }
    }

    /// The requested verbs that were neither installed nor attempted.
    public var notAttempted: [String] {
        requested.filter { !installed.contains($0) && !failed.contains($0) }
    }

    /// The requested verbs the bottle still lacks: failed ones first, then
    /// the ones never attempted.
    public var missing: [String] {
        failed + notAttempted
    }

    /// The overall result.
    public var status: Status {
        if !failed.isEmpty {
            return .failed
        }
        return notAttempted.isEmpty ? .complete : .incomplete
    }

    /// Whether a finished winetricks run installed its verb.
    ///
    /// - Parameters:
    ///   - exitCode: The process exit code, or `nil` if it never reported one.
    ///   - failure: The error the run reported instead of exiting, if any.
    /// - Returns: `true` only for a run that exited 0 without an error.
    public static func succeeded(exitCode: Int32?, failure: String?) -> Bool {
        failure == nil && exitCode == 0
    }

    /// Records how one verb's install finished.
    ///
    /// A verb that isn't in ``requested`` or was already recorded is ignored.
    ///
    /// - Parameters:
    ///   - verb: The verb that was installed.
    ///   - exitCode: The winetricks exit code, or `nil` if there was none.
    ///   - failure: The error the run reported, if any.
    public mutating func record(_ verb: String, exitCode: Int32?, failure: String?) {
        guard requested.contains(verb), !installed.contains(verb), !failed.contains(verb) else { return }
        if Self.succeeded(exitCode: exitCode, failure: failure) {
            installed.append(verb)
        } else {
            failed.append(verb)
        }
    }
}
