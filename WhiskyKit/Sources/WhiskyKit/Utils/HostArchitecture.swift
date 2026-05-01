//
//  HostArchitecture.swift
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

/// Hardware architecture of the host Mac, independent of which binary slice is running.
///
/// `#if arch(arm64)` is a compile-time check and would misreport Apple Silicon
/// hosts running an x86_64 slice through Rosetta as Intel. This queries
/// `hw.optional.arm64` via `sysctlbyname` so the answer reflects the actual CPU.
public enum HostArchitecture {
    /// Whether the host CPU is Apple Silicon. `false` on Intel Macs.
    public static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }()
}
