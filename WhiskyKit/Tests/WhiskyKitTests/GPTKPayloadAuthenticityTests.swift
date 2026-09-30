//
//  GPTKPayloadAuthenticityTests.swift
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

import Foundation
import Testing
@testable import WhiskyKit

/// Runs `tool` and returns its exit status and standard output.
private func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return (-1, "")
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
}

/// Whether this machine has what ``makeHalfSignedUniversalBinary(in:)``
/// needs: `lipo`, `codesign`, and a `/bin/ls` with arm64e and x86_64 slices.
private let canBuildHalfSignedBinary: Bool = {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") else { return false }
    let architectures = run("/usr/bin/lipo", ["-archs", "/bin/ls"]).output.split(whereSeparator: \.isWhitespace)
    return Set(architectures.map(String.init)).isSuperset(of: ["arm64e", "x86_64"])
}()

/// Builds the file the architecture check exists for: `/bin/ls` with its
/// Apple-signed arm64e slice kept and its x86_64 slice's signature stripped.
/// On Apple silicon the host's slice passes a check that looks at it alone,
/// while the slice Rosetta would load is unsigned. The signed slice is
/// returned on its own too, as the control.
private func makeHalfSignedUniversalBinary(in directory: URL) throws -> (universal: URL, signedSlice: URL) {
    let signed = directory.appending(path: "ls-arm64e").path(percentEncoded: false)
    let unsigned = directory.appending(path: "ls-x86_64").path(percentEncoded: false)
    let universal = directory.appending(path: "ls-half-signed").path(percentEncoded: false)
    let steps = [
        ["/usr/bin/lipo", "/bin/ls", "-thin", "arm64e", "-output", signed],
        ["/usr/bin/lipo", "/bin/ls", "-thin", "x86_64", "-output", unsigned],
        ["/usr/bin/codesign", "--remove-signature", unsigned],
        ["/usr/bin/lipo", "-create", signed, unsigned, "-output", universal]
    ]
    for step in steps {
        try #require(run(step[0], Array(step.dropFirst())).status == 0, "\(step.joined(separator: " ")) failed")
    }
    return (URL(filePath: universal), URL(filePath: signed))
}

@Suite("GPTK payload authenticity")
struct GPTKPayloadAuthenticityTests {
    private let tempDir: URL

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    // MARK: - Signature

    @Test(
        "A universal file with an unsigned slice fails even when its other slice is Apple's",
        .enabled(if: canBuildHalfSignedBinary, "needs lipo, codesign, and a /bin/ls with arm64e and x86_64 slices")
    )
    func refusesUnsignedSlice() throws {
        let binary = try makeHalfSignedUniversalBinary(in: tempDir)

        #expect(GPTKImporter.isAppleSigned(binary.signedSlice))
        #expect(!GPTKImporter.isAppleSigned(binary.universal))
    }
}
