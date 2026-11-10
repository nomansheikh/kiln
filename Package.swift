// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kiln",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KilnCore", targets: ["KilnCore"]),
    ],
    targets: [
        .target(name: "KilnCore"),
        .testTarget(name: "KilnCoreTests", dependencies: ["KilnCore"]),
    ]
)
