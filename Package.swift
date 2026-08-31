// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Camsthetics",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CamstheticsEngine",
            targets: ["CamstheticsEngine"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CamstheticsEngine",
            dependencies: [],
            path: "Sources/CamstheticsEngine"
        ),
        .testTarget(
            name: "CamstheticsEngineTests",
            dependencies: ["CamstheticsEngine"],
            path: "Tests/CamstheticsEngineTests"
        ),
    ]
)
