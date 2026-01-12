// swift-tools-version: 6.0
//
//  Package.swift
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

import PackageDescription

let package = Package(
    name: "WhiskyKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "WhiskyKit",
            targets: ["WhiskyKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftPackageIndex/SemanticVersion.git", from: "0.4.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3")
    ],
    targets: [
        .target(
            name: "WhiskyKit",
            dependencies: ["SemanticVersion"]
        ),
        .testTarget(
            name: "WhiskyKitTests",
            dependencies: ["WhiskyKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
