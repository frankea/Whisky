//
//  PEImportTableTests.swift
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

/// The bounded import-table parser the Electron and NW.js rule reads (#372).
@Suite("PE import tables")
final class PEImportTableTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pe_imports_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func table(_ fixture: PEImportFixture, truncatedTo length: Int? = nil) throws -> PEFile.ImportTable? {
        let url = folder.appending(path: "\(UUID().uuidString).exe")
        var data = fixture.data()
        if let length {
            data = data.prefix(length)
        }
        try data.write(to: url)
        return try PEFile(url: url).importTable()
    }

    @Test("A PE32+ image's normal and delay imports are read apart, lowercased")
    func pe32PlusTables() throws {
        let fixture = PEImportFixture(
            normalImports: ["KERNEL32.dll", "VERSION.dll"], delayImports: ["ffmpeg.dll", "d3d11.dll", "DXGI.dll"]
        )
        let imports = try #require(try table(fixture))
        #expect(imports.normalImports == ["kernel32.dll", "version.dll"])
        #expect(imports.delayImports == ["ffmpeg.dll", "d3d11.dll", "dxgi.dll"])
        #expect(imports.allImports.count == 5)
    }

    @Test("A PE32 image's tables are read too")
    func pe32Tables() throws {
        let fixture = PEImportFixture(
            pe32Plus: false,
            normalImports: ["nw.dll", "kernel32.dll"],
            delayImports: ["dwmapi.dll"]
        )
        let imports = try #require(try table(fixture))
        #expect(imports.normalImports == ["nw.dll", "kernel32.dll"])
        #expect(imports.delayImports == ["dwmapi.dll"])
    }

    @Test("An old delay descriptor holding virtual addresses resolves through the image base")
    func virtualAddressDelayDescriptor() throws {
        let fixture = PEImportFixture(pe32Plus: false, delayImports: ["ffmpeg.dll"], delayVirtualAddresses: true)
        let imports = try #require(try table(fixture))
        #expect(imports.delayImports == ["ffmpeg.dll"])
    }

    @Test("An image without data directories imports nothing")
    func noDataDirectories() throws {
        let fixture = PEImportFixture(normalImports: ["ffmpeg.dll"], numberOfRvaAndSizes: 0)
        let imports = try #require(try table(fixture))
        #expect(imports.normalImports.isEmpty)
        #expect(imports.delayImports.isEmpty)
    }

    @Test("Directories past the header's count are not read, even when the slots hold tables")
    func directoriesPastTheCount() throws {
        var fixture = PEImportFixture(
            normalImports: ["ffmpeg.dll"], delayImports: ["d3d11.dll"], numberOfRvaAndSizes: 0
        )
        fixture.directoriesPastCount = true
        let none = try #require(try table(fixture))
        #expect(none.allImports.isEmpty)

        // The import directory is index 1, the delay-load directory 13.
        fixture.numberOfRvaAndSizes = 2
        let normalOnly = try #require(try table(fixture))
        #expect(normalOnly.normalImports == ["ffmpeg.dll"])
        #expect(normalOnly.delayImports.isEmpty)
    }

    @Test("A directory cut short by the end of the file keeps what was read")
    func truncatedDirectory() throws {
        let fixture = PEImportFixture(normalImports: ["kernel32.dll", "user32.dll", "ffmpeg.dll"])
        // The first descriptor and half of the second.
        let cut = fixture.normalTableOffset + PEImportFixture.normalDescriptorSize + 10
        let imports = try #require(try table(fixture, truncatedTo: cut))
        #expect(imports.normalImports == ["kernel32.dll"])
        #expect(imports.delayImports.isEmpty)
    }

    @Test("A name outside the file is skipped, and the rest are read")
    func namePastEndOfFile() throws {
        let fixture = PEImportFixture(normalImports: ["kernel32.dll"], danglingNormalName: true)
        let imports = try #require(try table(fixture))
        #expect(imports.normalImports == ["kernel32.dll"])
    }

    @Test("A name in the section's zero-filled tail is skipped, though the file goes on past the section")
    func nameInZeroFilledTail() throws {
        var fixture = PEImportFixture(normalImports: ["kernel32.dll"], danglingNormalName: true)
        fixture.bytesBehindDanglingName = true
        let imports = try #require(try table(fixture))
        #expect(imports.normalImports == ["kernel32.dll"])
    }

    @Test("At most 1,024 descriptors are read across both tables")
    func descriptorCap() throws {
        let normal = (0 ..< 1_000).map { String(format: "lib%04d.dll", $0) }
        let delay = (0 ..< 100).map { String(format: "late%04d.dll", $0) }
        let imports = try #require(try table(PEImportFixture(normalImports: normal, delayImports: delay)))
        #expect(imports.normalImports.count == 1_000)
        #expect(imports.delayImports.count == PEFile.ImportTable.maxDescriptors - 1_000)
        #expect(imports.delayImports.contains("late0023.dll"))
        #expect(!imports.delayImports.contains("late0024.dll"))
    }

    @Test("The existing minimal fixtures parse with empty tables")
    func minimalFixtures() throws {
        for data in [PEBuilder.createMinimalPE32(), PEBuilder.createMinimalPE32Plus()] {
            let url = folder.appending(path: "\(UUID().uuidString).exe")
            try data.write(to: url)
            let imports = try #require(try PEFile(url: url).importTable())
            #expect(imports.allImports.isEmpty)
        }
    }
}
