// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// Set TXLEMETRY_SWIFT_PACKAGE_URL to build against a local or mirrored copy of the Txlemetry Apple SDK.
let txlemetryPackageURL = ProcessInfo.processInfo.environment["TXLEMETRY_SWIFT_PACKAGE_URL"].flatMap { $0.isEmpty ? nil : $0 }
    ?? "https://github.com/hectorvss/txlemetry-ios.git"

let package = Package(
    name: "txlemetry_flutter",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "txlemetry-flutter", targets: ["txlemetry_flutter"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(name: "Txlemetry", url: txlemetryPackageURL, .upToNextMajor(from: "4.0.0")),
    ],
    targets: [
        .target(
            name: "txlemetry_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Txlemetry", package: "Txlemetry"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
