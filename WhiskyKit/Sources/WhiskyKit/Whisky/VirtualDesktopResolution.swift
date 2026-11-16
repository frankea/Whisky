//
//  VirtualDesktopResolution.swift
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

import CoreGraphics
import Foundation

/// The Mac's main display, as Match Display sizes a virtual desktop to it.
public enum MainDisplay {
    /// The main display's size in backing pixels, or `nil` when there is no display mode.
    ///
    /// The main display is the one with the menu bar, where Wine opens its
    /// desktop window. A scaled Retina mode reports its backing size (a
    /// 1512x982-point mode is 3024x1964), the same pixels a screen's frame
    /// times its backing scale factor gives. Safe to call from any thread.
    public static func pixelSize() -> (width: Int, height: Int)? {
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()),
              mode.pixelWidth > 0, mode.pixelHeight > 0
        else { return nil }
        return (width: mode.pixelWidth, height: mode.pixelHeight)
    }
}

extension ResolutionPreset {
    /// The size used when Match Display cannot read the display, and the default preset's size.
    static let fallbackResolution = (width: 1_920, height: 1_080)

    /// The virtual desktop size Wine is given for this preset, as `WIDTHxHEIGHT`.
    ///
    /// The bottle's Display section and a program's virtual desktop override
    /// both resolve through here, so Match Display means the same size in both.
    ///
    /// - Parameters:
    ///   - customWidth: The width used by `.custom`.
    ///   - customHeight: The height used by `.custom`.
    ///   - displaySize: Reads the display size for `.matchDisplay`; only called
    ///     for that preset. Defaults to the main display.
    /// - Returns: A string like `"1920x1080"`.
    public func resolutionString(
        customWidth: Int,
        customHeight: Int,
        displaySize: () -> (width: Int, height: Int)? = MainDisplay.pixelSize
    ) -> String {
        let size = switch self {
        case .matchDisplay:
            displaySize() ?? Self.fallbackResolution
        case .custom:
            (width: customWidth, height: customHeight)
        default:
            dimensions ?? Self.fallbackResolution
        }
        return "\(size.width)x\(size.height)"
    }
}
