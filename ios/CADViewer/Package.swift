// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CADViewer",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CADViewer", targets: ["CADViewer"])
    ],
    dependencies: [
        // Geometry, viewport and transform maths: plain Swift, testable without Xcode.
        .package(path: "../DXFGeometry"),
        // Named again here, because DrawingLoader reads the file with SwiftDXF directly
        // rather than going through DXFGeometry. Relying on the transitive dependency would
        // build fine today and break the moment DXFGeometry changed its own imports.
        .package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "CADViewer",
            dependencies: [
                "DXFGeometry",
                .product(name: "SwiftDXF", package: "SwiftDXF")
            ],
            resources: [
                // The built DWG viewer; see ios/web/build-for-ios.sh.
                .copy("Resources/dwgviewer")
            ]
        ),
        .executableTarget(name: "CADViewerApp", dependencies: ["CADViewer"]),
        .testTarget(
            name: "CADViewerTests",
            dependencies: ["CADViewer", "DXFGeometry"]
        )
    ]
)
