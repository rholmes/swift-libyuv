// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-libyuv",
  platforms: [.iOS(.v13), .macOS(.v12), .macCatalyst(.v14), .tvOS(.v13)],
  products: [
    .library(name: "libyuv", targets: ["libyuv"]),
  ],
  targets: [
    .binaryTarget(
      name: "libyuvBinary",
      path: "Sources/libyuv.xcframework"),
    .target(
      name: "Clibyuv",
      dependencies: ["libyuvBinary"],
      sources: ["shim.c"],
      publicHeadersPath: "include/libyuv",
      cSettings: [
        .headerSearchPath("include") // gives -I Sources/libyuv/include
      ]
    ),
    .target(
      name: "libyuv",
      dependencies: ["Clibyuv"],
      sources: ["shim.swift"]
    ),
  ]
)
