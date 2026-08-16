// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SerialCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SerialCore", targets: ["SerialCore"])],
    targets: [
        .target(name: "SerialCore"),
        .testTarget(name: "SerialCoreTests", dependencies: ["SerialCore"]),
    ]
)
