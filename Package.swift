// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-libyuv",
    platforms: [.iOS(.v13), .macOS(.v12), .macCatalyst(.v14), .tvOS(.v13)],
    products: [
        .library(
            name: "libyuv",
            targets: ["libyuv"]),
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(name: "libyuv", path: "Sources/libyuv.xcframework")
    ]
)
