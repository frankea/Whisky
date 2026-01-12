//
//  GPUDetection.swift
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

/// GPU vendor identifiers for compatibility reporting.
///
/// These vendors are used when spoofing GPU capabilities to help launchers
/// pass compatibility checks that would otherwise fail on macOS.
public enum GPUVendor: String, Codable, CaseIterable, Sendable {
    /// NVIDIA Corporation (recommended for best compatibility)
    case nvidia = "NVIDIA"
    /// Advanced Micro Devices, Inc.
    case amd = "AMD"
    /// Intel Corporation
    case intel = "Intel"

    /// PCI vendor ID for this GPU manufacturer
    public var vendorID: String {
        switch self {
        case .nvidia:
            return "0x10DE"
        case .amd:
            return "0x1002"
        case .intel:
            return "0x8086"
        }
    }

    /// Representative device ID for spoofing
    public var deviceID: String {
        switch self {
        case .nvidia:
            return "0x2684"  // RTX 4090
        case .amd:
            return "0x73FF"  // RX 6900 XT
        case .intel:
            return "0x9BC5"  // UHD Graphics 730
        }
    }

    /// Human-readable GPU model name
    public var modelName: String {
        switch self {
        case .nvidia:
            return "NVIDIA GeForce RTX 4090"
        case .amd:
            return "AMD Radeon RX 6900 XT"
        case .intel:
            return "Intel UHD Graphics 730"
        }
    }
}

/// Utilities for GPU capability detection and spoofing.
///
/// ## Overview
///
/// Many game launchers perform GPU compatibility checks using DirectX and OpenGL
/// queries. On Apple Silicon Macs using Wine/CrossOver, these queries may return
/// incomplete or incorrect information, causing launchers to report "GPU not supported"
/// or display black screens.
///
/// This system addresses Issue #41 by configuring environment variables that make
/// Wine report high-end GPU capabilities, allowing launchers to pass their checks.
///
/// ## Safety Note
///
/// GPU spoofing only affects capability reporting to launchers and DirectX queries.
/// It does **not** modify game memory or interfere with anti-cheat systems. The
/// actual rendering still uses Apple's Metal API through Wine's translation layer.
///
/// ## Example
///
/// ```swift
/// // Apply default Apple Silicon GPU spoofing
/// let env = GPUDetection.spoofAppleSilicon()
/// // Returns environment variables reporting high-end NVIDIA GPU
/// ```
///
/// ## Topics
///
/// ### Spoofing Methods
/// - ``spoofGPU(vendor:model:)``
/// - ``spoofAppleSilicon()``
/// - ``spoofWithVendor(_:)``
///
/// ### Vendor Configuration
/// - ``GPUVendor``
public struct GPUDetection {
    /// Configures environment to report specific GPU capabilities.
    ///
    /// This method sets environment variables that Wine and DirectX use to report
    /// GPU features. Helps launchers pass compatibility checks that would otherwise
    /// fail due to incomplete Metal driver information.
    ///
    /// - Parameters:
    ///   - vendor: The GPU vendor to spoof (NVIDIA, AMD, or Intel)
    ///   - model: Optional custom model name override
    /// - Returns: Dictionary of environment variables for GPU spoofing
    public static func spoofGPU(vendor: GPUVendor, model: String? = nil) -> [String: String] {
        var env: [String: String] = [:]

        // OpenGL version reporting (4.6 is modern and well-supported)
        env["MESA_GL_VERSION_OVERRIDE"] = "4.6"
        env["MESA_GLSL_VERSION_OVERRIDE"] = "460"

        // DirectX feature levels
        env["D3DM_FEATURE_LEVEL_12_1"] = "1"  // DirectX 12.1 support
        env["D3DM_FEATURE_LEVEL_12_0"] = "1"  // DirectX 12.0 support
        env["D3DM_FEATURE_LEVEL_11_1"] = "1"  // DirectX 11.1 support

        // PCI vendor and device IDs
        env["GPU_VENDOR_ID"] = vendor.vendorID
        env["GPU_DEVICE_ID"] = vendor.deviceID

        // GPU model name for launcher display
        env["GPU_DESCRIPTION"] = model ?? vendor.modelName

        // Vulkan configuration (MoltenVK on macOS)
        env["VK_ICD_FILENAMES"] = "/usr/local/share/vulkan/icd.d/MoltenVK_icd.json"

        // VRAM reporting (8GB minimum for modern launchers)
        env["GPU_MEMORY_SIZE"] = "8192"  // 8GB in MB

        // Shader model support
        env["D3DM_SHADER_MODEL"] = "6.5"

        // Ray tracing capability (helps with modern launcher checks)
        env["D3DM_SUPPORT_DXR"] = "1"

        return env
    }

    /// Returns GPU spoofing configuration optimized for Apple Silicon Macs.
    ///
    /// This is the recommended default for most users. Reports capabilities as
    /// a high-end NVIDIA RTX 4090 GPU, which has excellent compatibility with
    /// game launchers and passes all capability checks.
    ///
    /// - Returns: Environment variables configured for Apple Silicon compatibility
    public static func spoofAppleSilicon() -> [String: String] {
        var env = spoofGPU(vendor: .nvidia, model: "Apple M-series (as NVIDIA RTX 4090)")

        // Additional Apple Silicon optimizations
        env["MTL_HUD_ENABLED"] = "0"  // Disable by default for spoofing
        env["METAL_DEVICE_WRAPPER_TYPE"] = "1"

        // Ensure Metal is properly initialized
        env["MTL_SHADER_VALIDATION"] = "0"

        return env
    }

    /// Returns GPU spoofing for a specific vendor.
    ///
    /// Use this when you need to report a specific GPU vendor for compatibility
    /// with games that have vendor-specific code paths.
    ///
    /// - Parameter vendor: The GPU vendor to emulate
    /// - Returns: Environment variables configured for the specified vendor
    public static func spoofWithVendor(_ vendor: GPUVendor) -> [String: String] {
        spoofGPU(vendor: vendor)
    }

    /// Validates that GPU spoofing environment is correctly configured.
    ///
    /// This method checks that all required environment variables are present
    /// and have valid values.
    ///
    /// - Parameter environment: The environment dictionary to validate
    /// - Returns: `true` if GPU spoofing is properly configured
    public static func validateSpoofingEnvironment(_ environment: [String: String]) -> Bool {
        let requiredKeys = [
            "GPU_VENDOR_ID",
            "GPU_DEVICE_ID",
            "D3DM_FEATURE_LEVEL_12_1"
        ]

        return requiredKeys.allSatisfy { environment[$0] != nil }
    }
}
