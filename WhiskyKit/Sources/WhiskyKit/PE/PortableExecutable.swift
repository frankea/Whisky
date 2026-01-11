//
//  PortableExecutable.swift
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
import AppKit

/// An error that occurred while parsing a PE file.
public struct PEError: Error {
    /// A human-readable description of the error.
    public let message: String

    /// Error indicating the file is not a valid PE executable.
    static let invalidPEFile = PEError(message: "Invalid PE file")
}

/// The processor architecture of a Windows executable.
///
/// This enum represents the target architecture for a PE file,
/// which determines whether it's a 32-bit or 64-bit executable.
public enum Architecture: Hashable {
    /// 32-bit x86 architecture (PE32).
    case x32
    /// 64-bit x86-64 architecture (PE32+).
    case x64
    /// Unknown or unsupported architecture.
    case unknown

    /// Returns a human-readable string representation of the architecture.
    ///
    /// - Returns: "32-bit", "64-bit", or `nil` for unknown architectures.
    public func toString() -> String? {
        switch self {
        case .x32:
            return "32-bit"
        case .x64:
            return "64-bit"
        default:
            return nil
        }
    }
}

/// A parser for Microsoft Portable Executable (PE) files.
///
/// `PEFile` reads and parses Windows executable files (.exe, .dll) to extract
/// metadata, icons, and architecture information. This is used by Whisky to
/// display program information and icons in the UI.
///
/// ## Overview
///
/// The PE format is the standard executable format for Windows. This struct
/// parses the key headers and sections needed to:
/// - Determine if a file is 32-bit or 64-bit
/// - Extract embedded icons for display
/// - Read the resource section for additional metadata
///
/// ## Example
///
/// ```swift
/// let peFile = try PEFile(url: executableURL)
/// print("Architecture: \(peFile.architecture.toString() ?? "unknown")")
///
/// if let icon = peFile.bestIcon() {
///     // Use icon in UI
/// }
/// ```
///
/// ## Topics
///
/// ### Creating a PEFile
/// - ``init(url:)-5k6lu``
/// - ``init(url:)-8ql55``
///
/// ### File Information
/// - ``url``
/// - ``architecture``
///
/// ### PE Headers
/// - ``coffFileHeader``
/// - ``optionalHeader``
/// - ``sections``
///
/// ### Resources
/// - ``rsrc``
/// - ``bestIcon()``
///
/// ## See Also
/// - [PE Format Documentation](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format)
public struct PEFile: Hashable, Equatable, Sendable {
    /// The URL to the PE file on disk.
    public let url: URL
    /// The COFF file header containing machine type and section count.
    public let coffFileHeader: COFFFileHeader
    /// The optional header containing the magic number and image base.
    ///
    /// This header is optional in COFF object files but always present
    /// in executable images.
    public let optionalHeader: OptionalHeader?
    /// The section table containing headers for each section.
    public let sections: [Section]

    /// Creates a PEFile from an optional URL.
    ///
    /// - Parameter url: The URL to the PE file, or `nil`.
    /// - Returns: A parsed `PEFile`, or `nil` if the URL was `nil`.
    /// - Throws: ``PEError`` if the file is not a valid PE executable.
    public init?(url: URL?) throws {
        guard let url else { return nil }
        try self.init(url: url)
    }

    /// Creates a PEFile by parsing the executable at the given URL.
    ///
    /// This initializer reads and parses the PE headers from the file.
    /// It validates the PE signature and extracts the COFF header,
    /// optional header, and section table.
    ///
    /// - Parameter url: The URL to the PE file.
    /// - Throws: ``PEError/invalidPEFile`` if the file is not a valid PE executable.
    public init(url: URL) throws {
        self.url = url
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }

        // (0x3C) Pointer to PE Header
        guard let peOffset = fileHandle.extract(UInt32.self, offset: 0x3C) else {
            throw PEError.invalidPEFile
        }
        var offset = UInt64(peOffset)
        guard let peHeader = fileHandle.extract(UInt32.self, offset: offset) else {
            throw PEError.invalidPEFile
        }
        // Check signature ("PE\0\0")
        guard peHeader.bigEndian == 0x50450000 else {
            throw PEError.invalidPEFile
        }

        let coffFileHeader = COFFFileHeader(handle: fileHandle, offset: offset)
        offset += 24 // Size of COFFHeader
        self.coffFileHeader = coffFileHeader

        if coffFileHeader.sizeOfOptionalHeader > 0 {
            self.optionalHeader = OptionalHeader(handle: fileHandle, offset: offset)
            offset += UInt64(coffFileHeader.sizeOfOptionalHeader)
        } else {
            self.optionalHeader = nil
        }

        var sections: [Section] = []
        for _ in 0..<coffFileHeader.numberOfSections {
            if let section = Section(handle: fileHandle, offset: offset) {
                sections.append(section)
            }
            offset += 40 // Size of Section
        }
        self.sections = sections
    }

    /// The ``Architecture`` of the executable
    public var architecture: Architecture {
        switch optionalHeader?.magic {
        case .pe32:
            return .x32
        case .pe32Plus:
            return .x64
        default:
            return .unknown
        }
    }

    /// Read the resource section
    /// 
    /// - Parameters:
    ///   - handle: The `FileHandle` to read the resource table section from.
    ///   - types: Only read entrys of the given types. Only applies to the root table. Default includes all types.
    /// - Returns: The resource table section
    private func rsrc(handle: FileHandle, types: [ResourceType] = ResourceType.allCases) -> ResourceDirectoryTable? {
        if let resourceSection = sections.first(where: { $0.name == ".rsrc" }) {
            return ResourceDirectoryTable(
                handle: handle,
                pointerToRawData: UInt64(resourceSection.pointerToRawData),
                types: types
            )
        } else {
            return nil
        }
    }

    /// The Resource Directory Table
    public var rsrc: ResourceDirectoryTable? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        return rsrc(handle: handle)
    }

    /// The best icon for this executable
    /// - Returns: An `NSImage` if there is a renderable icon in the resource directory table
    public func bestIcon() -> NSImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        guard let rsrc = rsrc(handle: handle, types: [.icon]) else { return nil }
        let icons = rsrc.allEntries
            .compactMap { entry -> NSImage? in
                guard let offset = entry.resolveRVA(sections: sections) else { return nil }
                let bitmapInfo = BitmapInfoHeader(handle: handle, offset: UInt64(offset))
                if bitmapInfo.size != 40 {
                    do {
                        try handle.seek(toOffset: UInt64(offset))
                        if let iconData = try handle.read(upToCount: Int(entry.size)) {
                            if let rep = NSBitmapImageRep(data: iconData) {
                                let image = NSImage(size: rep.size)
                                image.addRepresentation(rep)
                                return image
                            }
                        }
                    } catch {
                        print("Failed to get icon")
                    }
                } else if bitmapInfo.colorFormat != .unknown {
                    return bitmapInfo.renderBitmap(handle: handle, offset: UInt64(offset + bitmapInfo.size))
                }

                return nil
            }
            .filter { $0.isValid }

        if !icons.isEmpty {
            return icons.max(by: { $0.size.height < $1.size.height })
        } else {
            return NSImage()
        }
    }
}
