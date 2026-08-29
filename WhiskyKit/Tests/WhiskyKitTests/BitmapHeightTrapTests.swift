//
//  BitmapHeightTrapTests.swift
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

@Suite("Bitmap header height edge cases")
struct BitmapHeightTrapTests {
    private func header(height: Int32) throws -> (BitmapInfoHeader, FileHandle) {
        var params = BitmapHeaderParams()
        params.width = 16
        params.height = height
        let url = FileManager.default.temporaryDirectory.appending(path: "bmp-\(UUID().uuidString)")
        try createBitmapInfoHeaderData(params).write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        return (BitmapInfoHeader(handle: handle, offset: 0), handle)
    }

    @Test("Int32.min as the height is rejected instead of trapping in abs")
    func int32MinHeightIsRejected() throws {
        let (info, handle) = try header(height: Int32.min)
        defer { try? handle.close() }

        #expect(info.height == Int32.min)
        #expect(info.renderBitmap(handle: handle, offset: 40) == nil)
    }

    @Test("Other out-of-range heights are still rejected")
    func outOfRangeHeights() throws {
        for height: Int32 in [0, Int32.max, -(1 << 20), 1 << 20] {
            let (info, handle) = try header(height: height)
            defer { try? handle.close() }
            #expect(info.renderBitmap(handle: handle, offset: 40) == nil, "height \(height)")
        }
    }
}
