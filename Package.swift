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
        .library(
            name: "CamstheticsServices",
            targets: ["CamstheticsServices"]
        ),
        .library(
            name: "CamstheticsUI",
            targets: ["CamstheticsUI"]
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
        .target(
            name: "CamstheticsServices",
            // `docs/ARCHITECTURE.md`: "CamstheticsServices depends on
            // CamstheticsEngine (for domain models)" — this edge was
            // documented but never wired until Phase 3's VisionService
            // needed `SubjectCandidate`/`NormRect`/`SubjectCategory` (the
            // domain models `CamstheticsEngine` already defines and tests;
            // never duplicated here).
            dependencies: ["CamstheticsEngine"],
            path: "Sources/CamstheticsServices"
        ),
        .testTarget(
            name: "CamstheticsServicesTests",
            dependencies: ["CamstheticsServices"],
            path: "Tests/CamstheticsServicesTests"
        ),
        .target(
            name: "CamstheticsUI",
            dependencies: [],
            path: "Sources/CamstheticsUI"
        ),
        .testTarget(
            name: "CamstheticsUITests",
            dependencies: ["CamstheticsUI"],
            path: "Tests/CamstheticsUITests"
        ),
    ]
)
