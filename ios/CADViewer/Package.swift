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
        .package(path: "../DXFGeometry")
    ],
    targets: [
        .target(
            name: "CADViewer",
            dependencies: ["DXFGeometry"],
            resources: [
                // The built DWG viewer; see ios/web/build-for-ios.sh.
                .copy("Resources/dwgviewer")
            ]
        ),
        .executableTarget(name: "CADViewerApp", dependencies: ["CADViewer"]),
        .testTarget(name: "CADViewerTests", dependencies: ["CADViewer", "DXFGeometry"])
    ]
)
