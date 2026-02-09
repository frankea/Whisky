//
//  GraphicsBackendResolver.swift
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
import os.log

/// Resolves the `.recommended` graphics backend to a concrete backend.
///
/// This is a caseless enum (static methods only) following the ``GPUDetection`` pattern.
/// The resolver centralises the heuristic so that future improvements (e.g., preferring
/// DXVK on specific GPU families) can be made without changing the data model or UI.
public enum GraphicsBackendResolver {
    /// Resolves the recommended graphics backend for the current system.
    ///
    /// D3DMetal is the default and best-supported path on macOS 15+ Apple Silicon.
    /// Future versions may adjust based on GPU family or macOS version.
    ///
    /// - Parameter macOSVersion: The macOS version to consider. Defaults to the running system.
    /// - Returns: A concrete ``GraphicsBackend`` (never `.recommended`).
    public static func resolve(macOSVersion: MacOSVersion = .current) -> GraphicsBackend {
        // D3DMetal is Wine's native Metal translation layer and the best-supported
        // path on Apple Silicon. The architecture supports future heuristic
        // sophistication without changing the data model.
        .d3dMetal
    }

    /// Returns a localized explanation for the recommended backend choice.
    ///
    /// Suitable for display in a detail label or tooltip next to the "Recommended" option.
    ///
    /// - Parameter macOSVersion: The macOS version to consider. Defaults to the running system.
    /// - Returns: A human-readable rationale string.
    public static func rationale(macOSVersion: MacOSVersion = .current) -> String {
        String(localized: "config.graphics.backend.recommended.rationale")
    }
}
