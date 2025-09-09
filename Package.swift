// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swift-libyuv",
  platforms: [.iOS(.v13), .macOS(.v12), .macCatalyst(.v14), .tvOS(.v13)],
  products: [
    .library(name: "libyuv", targets: ["clibyuv"]),
  ],
  targets: [
    // 1) Binary to link (xcframework must not contain a module.modulemap)
    .binaryTarget(
      name: "libyuvBinary",
      path: "Sources/libyuv.xcframework"
    ),

    // 2) C shim that vends headers + module; depends on the binary for linking
    .target(
      name: "clibyuv",
      dependencies: ["libyuvBinary"],
      path: "Sources/clibyuv",
      publicHeadersPath: "include"
      // add cSettings/headerSearchPath here only if you have extra nested dirs
    ),
  ]
)
