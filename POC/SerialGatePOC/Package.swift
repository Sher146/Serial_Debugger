// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SerialGatePOC",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/SerialCore"),
        .package(
            url: "https://github.com/Kyome22/SerialGate",
            revision: "845805702b9da4c5612fc13f17589588eaa83801"
        ),
    ],
    targets: [
        .target(
            name: "SerialGateAdapter",
            dependencies: [
                .product(name: "SerialCore", package: "SerialCore"),
                .product(name: "SerialGate", package: "SerialGate"),
            ]
        ),
        .executableTarget(
            name: "poc-cli",
            dependencies: [
                .product(name: "SerialCore", package: "SerialCore"),
                "SerialGateAdapter",
            ]
        ),
        .testTarget(
            name: "SerialGateAdapterTests",
            dependencies: [
                .product(name: "SerialCore", package: "SerialCore"),
                "SerialGateAdapter",
            ]
        ),
    ]
)
