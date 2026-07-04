// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TsuretekuContent",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "TsuretekuContent",
            targets: ["TsuretekuContent"]),
    ],
    targets: [
        .target(
            name: "TsuretekuContent"),
    ]
)
