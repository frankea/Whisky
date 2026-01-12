//
//  GPUDetectionTests.swift
//  WhiskyKitTests
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

import XCTest
@testable import WhiskyKit

final class GPUDetectionTests: XCTestCase {
    func testNVIDIAVendorID() throws {
        XCTAssertEqual(GPUVendor.nvidia.vendorID, "0x10DE")
        XCTAssertEqual(GPUVendor.nvidia.modelName, "NVIDIA GeForce RTX 4090")
    }

    func testAMDVendorID() throws {
        XCTAssertEqual(GPUVendor.amd.vendorID, "0x1002")
        XCTAssertEqual(GPUVendor.amd.modelName, "AMD Radeon RX 6900 XT")
    }

    func testIntelVendorID() throws {
        XCTAssertEqual(GPUVendor.intel.vendorID, "0x8086")
    }

    func testGPUSpoofingIncludesVendorID() throws {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        XCTAssertEqual(env["GPU_VENDOR_ID"], "0x10DE")
        XCTAssertNotNil(env["GPU_DEVICE_ID"])
    }

    func testGPUSpoofingIncludesFeatureLevels() throws {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report DirectX 12.1 support
        XCTAssertEqual(env["D3DM_FEATURE_LEVEL_12_1"], "1")
        XCTAssertEqual(env["D3DM_FEATURE_LEVEL_12_0"], "1")
        XCTAssertEqual(env["D3DM_FEATURE_LEVEL_11_1"], "1")
    }

    func testGPUSpoofingIncludesOpenGLVersion() throws {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report OpenGL 4.6
        XCTAssertEqual(env["MESA_GL_VERSION_OVERRIDE"], "4.6")
        XCTAssertEqual(env["MESA_GLSL_VERSION_OVERRIDE"], "460")
    }

    func testGPUSpoofingIncludesVRAM() throws {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report at least 8GB VRAM
        XCTAssertEqual(env["GPU_MEMORY_SIZE"], "8192")
    }

    func testGPUSpoofingIncludesRayTracing() throws {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report DXR support
        XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
    }

    func testAppleSiliconSpoofing() throws {
        let env = GPUDetection.spoofAppleSilicon()

        // Should spoof as NVIDIA for best compatibility
        XCTAssertEqual(env["GPU_VENDOR_ID"], "0x10DE")

        // Should include Metal-specific settings
        XCTAssertNotNil(env["MTL_SHADER_VALIDATION"])
    }

    func testCustomModelName() throws {
        let customModel = "Custom GPU Name"
        let env = GPUDetection.spoofGPU(vendor: .amd, model: customModel)

        XCTAssertEqual(env["GPU_DESCRIPTION"], customModel)
    }

    func testSpoofWithVendor() throws {
        let nvidiaEnv = GPUDetection.spoofWithVendor(.nvidia)
        let amdEnv = GPUDetection.spoofWithVendor(.amd)

        XCTAssertEqual(nvidiaEnv["GPU_VENDOR_ID"], "0x10DE")
        XCTAssertEqual(amdEnv["GPU_VENDOR_ID"], "0x1002")
    }

    func testValidateSpoofingEnvironment() throws {
        // Valid environment
        var validEnv = GPUDetection.spoofGPU(vendor: .nvidia)
        XCTAssertTrue(GPUDetection.validateSpoofingEnvironment(validEnv))

        // Invalid environment (missing required keys)
        validEnv.removeValue(forKey: "GPU_VENDOR_ID")
        XCTAssertFalse(GPUDetection.validateSpoofingEnvironment(validEnv))
    }

    func testAllVendorsHaveDeviceIDs() throws {
        for vendor in GPUVendor.allCases {
            XCTAssertFalse(vendor.vendorID.isEmpty)
            XCTAssertFalse(vendor.deviceID.isEmpty)
            XCTAssertFalse(vendor.modelName.isEmpty)
        }
    }

    func testVulkanConfiguration() throws {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should include MoltenVK ICD path
        XCTAssertNotNil(env["VK_ICD_FILENAMES"])
        XCTAssertTrue(env["VK_ICD_FILENAMES"]?.contains("MoltenVK") ?? false)
    }

    func testShaderModelSupport() throws {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report modern shader model
        XCTAssertEqual(env["D3DM_SHADER_MODEL"], "6.5")
    }
}
