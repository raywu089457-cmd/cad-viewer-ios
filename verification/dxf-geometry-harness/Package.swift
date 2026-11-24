// swift-tools-version: 5.9
import PackageDescription

// A separate package, not targets inside ios/DXFGeometry.
//
// The harnesses are executables with top-level code in `main.swift`. Putting them in the
// library package would make SwiftPM build them for every consumer and would clash with
// the library's own entry points. Living here, they depend on the geometry exactly the way
// an app does, so `swift run` exercises the real module boundary.
let package = Package(
    name: "Harness",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../ios/DXFGeometry"),
        // Pulled in transitively, but named here because the harnesses read DXF directly.
        .package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "verify",
            dependencies: [
                .product(name: "DXFGeometry", package: "DXFGeometry"),
                .product(name: "SwiftDXF", package: "SwiftDXF")
            ]
        ),
        .executableTarget(
            name: "scenecheck",
            dependencies: [
                .product(name: "DXFGeometry", package: "DXFGeometry"),
                .product(name: "SwiftDXF", package: "SwiftDXF")
            ]
        )
    ]
)
