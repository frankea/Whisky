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

@testable import WhiskyKit
import XCTest

final class GPUDetectionTests: XCTestCase {
    func testNVIDIAVendorID() {
        XCTAssertEqual(GPUVendor.nvidia.vendorID, "0x10DE")
        XCTAssertEqual(GPUVendor.nvidia.modelName, "NVIDIA GeForce RTX 4090")
    }

    func testAMDVendorID() {
        XCTAssertEqual(GPUVendor.amd.vendorID, "0x1002")
        XCTAssertEqual(GPUVendor.amd.modelName, "AMD Radeon RX 6900 XT")
    }

    func testIntelVendorID() {
        XCTAssertEqual(GPUVendor.intel.vendorID, "0x8086")
    }

    func testGPUSpoofingOmitsUnreadVendorKeys() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia, model: "Custom GPU Name")

        // No shipped runtime reads any of these, so the spoof doesn't set them.
        XCTAssertNil(env["GPU_VENDOR_ID"])
        XCTAssertNil(env["GPU_DEVICE_ID"])
        XCTAssertNil(env["GPU_DESCRIPTION"])
        XCTAssertNil(env["GPU_MEMORY_SIZE"])
        XCTAssertNil(env["D3DM_SHADER_MODEL"])
    }

    func testGPUSpoofingOmitsUnreadFeatureLevelKeys() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // D3DMetal, Wine, DXVK and DXMT read none of these, so the spoof
        // doesn't set them.
        XCTAssertNil(env["D3DM_FEATURE_LEVEL_12_1"])
        XCTAssertNil(env["D3DM_FEATURE_LEVEL_12_0"])
        XCTAssertNil(env["D3DM_FEATURE_LEVEL_11_1"])
    }

    func testGPUSpoofingIncludesOpenGLVersion() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report OpenGL 4.6
        XCTAssertEqual(env["MESA_GL_VERSION_OVERRIDE"], "4.6")
        XCTAssertEqual(env["MESA_GLSL_VERSION_OVERRIDE"], "460")
    }

    func testGPUSpoofingIncludesRayTracing() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report DXR support
        XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
    }

    func testAppleSiliconSpoofing() {
        let env = GPUDetection.spoofAppleSilicon()

        // Should include Metal-specific settings
        XCTAssertNotNil(env["MTL_SHADER_VALIDATION"])
    }

    func testSpoofWithVendor() {
        let nvidiaEnv = GPUDetection.spoofWithVendor(.nvidia)
        let amdEnv = GPUDetection.spoofWithVendor(.amd)

        XCTAssertEqual(nvidiaEnv, GPUDetection.spoofGPU(vendor: .nvidia))
        XCTAssertEqual(amdEnv, GPUDetection.spoofGPU(vendor: .amd))
    }

    func testValidateSpoofingEnvironment() {
        // Valid environment
        var validEnv = GPUDetection.spoofGPU(vendor: .nvidia)
        XCTAssertTrue(GPUDetection.validateSpoofingEnvironment(validEnv))

        // Invalid environment (missing required keys)
        validEnv.removeValue(forKey: "MESA_GL_VERSION_OVERRIDE")
        XCTAssertFalse(GPUDetection.validateSpoofingEnvironment(validEnv))
    }

    func testAllVendorsHaveDeviceIDs() {
        for vendor in GPUVendor.allCases {
            XCTAssertFalse(vendor.vendorID.isEmpty)
            XCTAssertFalse(vendor.deviceID.isEmpty)
            XCTAssertFalse(vendor.modelName.isEmpty)
        }
    }

    func testNoHardcodedVulkanICDPath() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // The old value pointed at /usr/local/share, which exists on no user
        // machine; the runtime carries its own MoltenVK configuration.
        XCTAssertNil(env["VK_ICD_FILENAMES"])
    }
}
