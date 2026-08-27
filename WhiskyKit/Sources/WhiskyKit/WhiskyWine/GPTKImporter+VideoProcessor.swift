//
//  GPTKImporter+VideoProcessor.swift
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

enum GPTKVideoProcessorError: Error, Equatable {
    /// The DLL is not shaped like the PE the rename expects.
    case malformedPE(String)
    /// The export directory holds a name the rename was not written for.
    case unexpectedExportName(String)
}

/// D3DMetal answers `QueryInterface` for `ID3D12VideoDevice` with
/// `E_NOINTERFACE`, so a game that decodes video itself and asks D3D12 to
/// convert NV12 to RGB gets nothing and falls back to a path no Windows machine
/// runs. S.T.A.L.K.E.R. Call of Pripyat EE draws its intro at half resolution
/// with the chroma flat, the olive artifact.
///
/// The runtime ships an interposer that supplies the missing video processor.
/// It cannot simply be installed at build time: it has to sit in the `d3d12.dll`
/// builtin slot with Apple's DLL renamed alongside it, and Apple's DLL only
/// exists once the payload here is deployed. So the swap happens on deploy.
/// One builtin slot the runtime interposes: which shim goes in, and what Apple's
/// DLL is called once it has been moved aside.
///
/// The two we ship are the same operation, so they share one implementation
/// rather than two files that drift.
struct GPTKInterposer: Sendable {
    /// The shim's filename under `lib/gptk-video` in the runtime.
    let shimFileName: String
    /// The builtin slot it takes over.
    let slotName: String
    /// Apple's DLL under its second name. It can never be longer than
    /// ``slotName``: the export name is patched in place, so it cannot grow.
    let renamedName: String
    /// The unix half beside the renamed PE, without which D3DMetal never binds.
    let renamedUnixName: String
    /// What to call it in a log line.
    let label: String
}

extension GPTKImporter {
    /// D3DMetal supplies no `ID3D12VideoDevice`, so a game that decodes video
    /// itself and asks D3D12 to convert NV12 to RGB gets `E_NOINTERFACE`.
    static let videoProcessorInterposer = GPTKInterposer(
        shimFileName: "d3d12shim.dll",
        slotName: "d3d12.dll",
        renamedName: "d3dmt.dll",
        renamedUnixName: "d3dmt.so",
        label: "D3D12 video processor"
    )

    /// D3DMetal's `IDXGIAdapter::CheckInterfaceSupport` returns success and
    /// writes -1 for the driver version. Engines format that as four words and
    /// read "65535.65535.65535.65535", then refuse to run: Helldivers 2 puts a
    /// modal "GPU drivers are out of date" box in front of the game.
    static let dxgiVersionInterposer = GPTKInterposer(
        shimFileName: "dxgishim.dll",
        slotName: "dxgi.dll",
        renamedName: "dxgm.dll",
        renamedUnixName: "dxgm.so",
        label: "DXGI driver version"
    )

    /// Every slot we interpose, in the order they are installed.
    static let interposers = [videoProcessorInterposer, dxgiVersionInterposer]

    static func shim(for interposer: GPTKInterposer, inLibraryFolder folder: URL) -> URL {
        folder.appending(path: "Wine").appending(path: "lib")
            .appending(path: "gptk-video").appending(path: interposer.shimFileName)
    }

    /// Where the runtime ships the interposer, if it is new enough to carry one.
    static let videoProcessorShimPath = ["lib", "gptk-video", "d3d12shim.dll"]
    /// Apple's D3D12 under its second name. Nine characters, and that is not a
    /// style choice: the export name is patched in place, so it cannot grow.
    static let videoDeviceDLLName = "d3dmt.dll"
    static let videoDeviceUnixName = "d3dmt.so"
    static let videoProcessorSlotName = "d3d12.dll"

    static func videoProcessorShim(inLibraryFolder folder: URL) -> URL {
        videoProcessorShimPath.reduce(folder.appending(path: "Wine")) { $0.appending(path: $1) }
    }

    /// Whether `folder`'s runtime carries an interposer to install at all.
    /// Runtimes older than the one that introduced it simply do without.
    static func has(_ interposer: GPTKInterposer, inLibraryFolder folder: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: shim(for: interposer, inLibraryFolder: folder).path(percentEncoded: false)
        )
    }

    static func hasVideoProcessor(inLibraryFolder folder: URL) -> Bool {
        has(videoProcessorInterposer, inLibraryFolder: folder)
    }

    /// Whether the interposer currently occupies the `d3d12.dll` slot.
    static func isInstalled(_ interposer: GPTKInterposer, inLibraryFolder folder: URL) -> Bool {
        let peDir = folder.appending(path: "Wine").appending(path: "lib")
            .appending(path: "wine").appending(path: "x86_64-windows")
        return FileManager.default.contentsEqual(
            atPath: peDir.appending(path: interposer.slotName).path(percentEncoded: false),
            andPath: shim(for: interposer, inLibraryFolder: folder).path(percentEncoded: false)
        )
    }

    static func isVideoProcessorInstalled(inLibraryFolder folder: URL) -> Bool {
        isInstalled(videoProcessorInterposer, inLibraryFolder: folder)
    }

    /// Puts the interposer in the `d3d12.dll` slot with Apple's DLL renamed
    /// beside it. Expects `d3d12.dll` to be Apple's, which is what deploy leaves
    /// behind, and does nothing if the runtime ships no interposer or the swap
    /// is already in place.
    static func install(_ interposer: GPTKInterposer, intoLibraryFolder folder: URL) throws {
        let fileManager = FileManager.default
        let shim = shim(for: interposer, inLibraryFolder: folder)
        guard has(interposer, inLibraryFolder: folder) else { return }
        guard !isInstalled(interposer, inLibraryFolder: folder) else { return }

        let wineLib = folder.appending(path: "Wine").appending(path: "lib")
        let peDir = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
        let unixDir = wineLib.appending(path: "wine").appending(path: "x86_64-unix")
        let slot = peDir.appending(path: interposer.slotName)
        let renamed = peDir.appending(path: interposer.renamedName)

        guard fileManager.fileExists(atPath: slot.path(percentEncoded: false)) else { return }

        if fileManager.fileExists(atPath: renamed.path(percentEncoded: false)) {
            try fileManager.removeItem(at: renamed)
        }
        try fileManager.copyItem(at: slot, to: renamed)
        try rewriteExportName(at: renamed, from: interposer.slotName, to: interposer.renamedName)

        // The renamed PE needs its own unix half or D3DMetal never binds.
        let link = unixDir.appending(path: interposer.renamedUnixName)
        try? fileManager.removeItem(at: link)
        try fileManager.createSymbolicLink(
            atPath: link.path(percentEncoded: false),
            withDestinationPath: unixLinkDestination
        )

        // Stage the shim beside the slot and swap by rename. Removing the slot
        // before copying left a window where a crash strands the tree with no
        // d3d12.dll at all, a state the guard above then refuses to repair.
        let staged = peDir.appending(path: interposer.slotName + ".staging")
        try? fileManager.removeItem(at: staged)
        try fileManager.copyItem(at: shim, to: staged)
        _ = try fileManager.replaceItemAt(slot, withItemAt: staged)
        let moved = "\(interposer.label): Apple's \(interposer.slotName) is now \(interposer.renamedName)"
        logger.info("Installed \(moved, privacy: .public)")
    }

    static func installVideoProcessor(intoLibraryFolder folder: URL) throws {
        try install(videoProcessorInterposer, intoLibraryFolder: folder)
    }

    /// Takes the interposer back out and restores Apple's DLL into the slot from
    /// the store, which is the only pristine copy: the renamed one on disk has a
    /// rewritten export name and cannot go back as `d3d12.dll`.
    ///
    /// Removal has to happen before the payload itself is removed, or the slot
    /// still holds the interposer, does not byte-match the store, and the
    /// restore loop skips it and leaves the tree with no working D3D12 at all.
    static func remove(
        _ interposer: GPTKInterposer, fromLibraryFolder folder: URL, usingStore store: URL
    ) {
        let fileManager = FileManager.default
        let wineLib = folder.appending(path: "Wine").appending(path: "lib")
        let peDir = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
        let unixDir = wineLib.appending(path: "wine").appending(path: "x86_64-unix")
        let slot = peDir.appending(path: interposer.slotName)

        if isInstalled(interposer, inLibraryFolder: folder) {
            let pristine = store.appending(path: "lib").appending(path: "wine")
                .appending(path: "x86_64-windows").appending(path: interposer.slotName)
            if fileManager.fileExists(atPath: pristine.path(percentEncoded: false)) {
                try? fileManager.removeItem(at: slot)
                try? fileManager.copyItem(at: pristine, to: slot)
            }
        }
        try? fileManager.removeItem(at: peDir.appending(path: interposer.renamedName))
        try? fileManager.removeItem(at: unixDir.appending(path: interposer.renamedUnixName))
    }

    static func removeVideoProcessor(fromLibraryFolder folder: URL, usingStore store: URL) {
        for interposer in interposers {
            remove(interposer, fromLibraryFolder: folder, usingStore: store)
        }
    }

    // MARK: - Prefixes

    /// Drops a placeholder for the renamed DLL into a prefix's `system32`.
    ///
    /// Without one the loader never looks in the builtin directory at all and
    /// the interposer cannot reach Apple's DLL, which would take D3D12 down
    /// with it. `wineboot` writes these when a prefix is made or updated, so new
    /// bottles get it for free; bottles that already exist predate the name and
    /// would otherwise need a prefix update before they could run anything.
    static func seedPlaceholder(
        for interposer: GPTKInterposer, inBottle bottle: URL, fromLibraryFolder folder: URL
    ) {
        let fileManager = FileManager.default
        let source = folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: interposer.renamedName)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return }

        let system32 = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32")
        guard fileManager.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        let placeholder = system32.appending(path: interposer.renamedName)
        guard !fileManager.fileExists(atPath: placeholder.path(percentEncoded: false)) else { return }
        try? fileManager.copyItem(at: source, to: placeholder)
    }

    static func seedVideoDevicePlaceholder(inBottle bottle: URL, fromLibraryFolder folder: URL) {
        seedPlaceholder(for: videoProcessorInterposer, inBottle: bottle, fromLibraryFolder: folder)
    }

    /// Installs the video processor if the payload is already deployed, and
    /// seeds every bottle's placeholder.
    ///
    /// This is the path for installs that were already set up before the
    /// interposer existed: they have the payload deployed and never run a deploy
    /// again, so without this they would keep rendering video through the
    /// engine's broken fallback until they happened to reimport. Idempotent and
    /// cheap enough to run at launch.
    public static func ensureVideoProcessorInstalled(bottles: [URL]) {
        let folder = WhiskyWineInstaller.libraryFolder
        guard isDeployed(inLibraryFolder: folder), hasVideoProcessor(inLibraryFolder: folder) else {
            return
        }
        do {
            try installVideoProcessor(intoLibraryFolder: folder)
        } catch {
            logger.error("Installing the D3D12 video processor failed: \(error.localizedDescription)")
            return
        }
        for bottle in bottles {
            seedVideoDevicePlaceholder(inBottle: bottle, fromLibraryFolder: folder)
        }
    }

    // MARK: - The rename

    /// Rewrites a PE's export directory name in place.
    ///
    /// Wine keys builtins on the name a DLL declares in its export directory,
    /// not on its filename, so a plain copy of Apple's D3D12 still says
    /// `d3d12.dll` and dedups against the original: `LoadLibrary` hands back the
    /// module that is already loaded and the interposer forwards into itself.
    /// Patching in place is what caps the new name at the old one's length.
    static func rewriteExportName(at url: URL, from old: String, to new: String) throws {
        let oldBytes = Array(old.utf8), newBytes = Array(new.utf8)
        guard oldBytes.count == newBytes.count else {
            throw GPTKVideoProcessorError.malformedPE("the replacement name must be the same length")
        }

        var data = try Data(contentsOf: url)
        let image = try PEImage(data: data)
        let nameOffset = try image.fileOffset(of: image.u32(image.exportDirectoryOffset + 12))
        guard nameOffset + oldBytes.count <= data.count else {
            throw GPTKVideoProcessorError.malformedPE("the export name runs past the end of the file")
        }

        let found = (0 ..< oldBytes.count).map { data[data.startIndex + nameOffset + $0] }
        guard found == oldBytes else {
            throw GPTKVideoProcessorError.unexpectedExportName(
                String(bytes: found, encoding: .utf8) ?? "unreadable"
            )
        }
        for (index, value) in newBytes.enumerated() {
            data[data.startIndex + nameOffset + index] = value
        }
        try data.write(to: url)
    }
}

/// Just enough of a PE to find the export directory's name string: the section
/// table, so a relative virtual address can be turned into a file offset, and
/// the export directory itself.
struct PEImage {
    struct Section {
        let virtualAddress: Int
        let virtualSize: Int
        let rawPointer: Int
    }

    private let data: Data
    private let sections: [Section]
    /// The export directory's own position in the file.
    let exportDirectoryOffset: Int

    init(data: Data) throws {
        self.data = data

        let peHeader = try Self.u32(data, 0x3C)
        guard try Self.u32(data, peHeader) == 0x0000_4550 else {
            throw GPTKVideoProcessorError.malformedPE("no PE signature at e_lfanew")
        }
        let sectionCount = try Self.u16(data, peHeader + 6)
        let optionalHeaderSize = try Self.u16(data, peHeader + 20)
        let optionalHeader = peHeader + 24
        // PE32+ carries eight more bytes of image base and four 64 bit sizes
        // before the data directories than PE32 does.
        let directories = try optionalHeader + (Self.u16(data, optionalHeader) == 0x20B ? 112 : 96)
        let exportDirectoryRVA = try Self.u32(data, directories)
        guard exportDirectoryRVA != 0 else {
            throw GPTKVideoProcessorError.malformedPE("no export directory")
        }

        let sectionTable = optionalHeader + optionalHeaderSize
        sections = try (0 ..< sectionCount).map { index in
            let entry = sectionTable + index * 40
            return try Section(
                virtualAddress: Self.u32(data, entry + 12),
                virtualSize: Self.u32(data, entry + 8),
                rawPointer: Self.u32(data, entry + 20)
            )
        }

        exportDirectoryOffset = try Self.fileOffset(of: exportDirectoryRVA, in: sections)
    }

    func u32(_ offset: Int) throws -> Int { try Self.u32(data, offset) }

    func fileOffset(of rva: Int) throws -> Int { try Self.fileOffset(of: rva, in: sections) }

    private static func fileOffset(of rva: Int, in sections: [Section]) throws -> Int {
        for section in sections
            where rva >= section.virtualAddress && rva < section.virtualAddress + max(section.virtualSize, 1) {
            return section.rawPointer + (rva - section.virtualAddress)
        }
        throw GPTKVideoProcessorError.malformedPE("rva \(rva) is not inside any section")
    }

    private static func byte(_ data: Data, _ offset: Int) throws -> Int {
        guard offset >= 0, offset < data.count else {
            throw GPTKVideoProcessorError.malformedPE("offset \(offset) is past the end of the file")
        }
        return Int(data[data.startIndex + offset])
    }

    private static func u16(_ data: Data, _ offset: Int) throws -> Int {
        try byte(data, offset) | (byte(data, offset + 1) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) throws -> Int {
        try u16(data, offset) | (u16(data, offset + 2) << 16)
    }
}
