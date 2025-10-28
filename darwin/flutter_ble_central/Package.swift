// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_ble_central",
    platforms: [
        .iOS("13.0"),
        .macOS("10.14")
    ],
    products: [
        .library(name: "flutter-ble-central", targets: ["flutter_ble_central"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_ble_central",
            dependencies: [],
            resources: [
                .process("Resources"),
            ]
        )
    ]
)
