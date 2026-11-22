// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DXFGeometry",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DXFGeometry", targets: ["DXFGeometry"]),
        // Re-exported so an app can import one module and still read DXF files.
        .library(name: "SwiftDXFReexport", targets: ["SwiftDXFReexport"])
    ],
    dependencies: [
        // MIT, dependency-free DXF reader. Pinned to a tag rather than vendored, so this
        // repository does not carry a copy of someone else's code.
        .package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "DXFGeometry",
            dependencies: [.product(name: "SwiftDXF", package: "SwiftDXF")]
        ),
        // A thin shim that re-exports the reader, so callers get `DXF` from one import.
        .target(
            name: "SwiftDXFReexport",
            dependencies: [.product(name: "SwiftDXF", package: "SwiftDXF")]
        ),
        .testTarget(name: "DXFGeometryTests", dependencies: ["DXFGeometry"])
    ]
)
