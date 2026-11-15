//
//  ShortcutIcon.swift
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

import AppKit
import Foundation
import ImageIO
import os.log
import UniformTypeIdentifiers

/// Writes a shortcut bundle's icon as an `.icns` file.
///
/// An icon inside the bundle travels with the app. A Finder custom icon is
/// file metadata instead, which iCloud Desktop sync can drop and which needs
/// the QuickLook thumbnail extension to produce anything at all.
enum ShortcutIcon {
    /// The square sizes, in pixels, written into the `.icns`.
    static let sizes = [16, 32, 128, 256, 512]

    /// Writes `image` as an `.icns` file at `url`, creating its folder.
    ///
    /// - Returns: Whether the file was written.
    static func write(_ image: NSImage, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            Logger.wineKit.error("Failed to create shortcut resources: \(error.localizedDescription)")
            return false
        }

        let rendered = sizes.compactMap { render(image, side: $0) }
        guard !rendered.isEmpty,
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.icns.identifier as CFString,
                  rendered.count,
                  nil
              )
        else { return false }

        for bitmap in rendered {
            CGImageDestinationAddImage(destination, bitmap, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    /// `image` drawn into a `side` by `side` bitmap.
    static func render(_ image: NSImage, side: Int) -> CGImage? {
        var proposed = CGRect(x: 0, y: 0, width: side, height: side)
        guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}
