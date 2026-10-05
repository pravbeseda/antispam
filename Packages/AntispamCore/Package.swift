// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AntispamCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AntispamCore", targets: ["AntispamCore"]),
    ],
    targets: [
        .target(name: "AntispamCore"),
        .testTarget(name: "AntispamCoreTests", dependencies: ["AntispamCore"]),
    ]
)
