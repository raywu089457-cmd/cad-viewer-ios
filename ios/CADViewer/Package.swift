// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CADViewer",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CADViewer", targets: ["CADViewer"])
    ],
    dependencies: [
        // Geometry, viewport, transform maths and the file routing: plain Swift with no
        // UIKit, CoreGraphics or SwiftUI, so all of it is testable without Xcode.
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
        .executableTarget(name: "CADViewerApp", dependencies: ["CADViewer"])
        // No test target. Everything here is SwiftUI, WebKit or PDFKit, which needs a
        // simulator to exercise; the logic it uses was moved to DXFGeometry, where
        // `swift test` runs it on any machine. A test target here could only test the
        // boring part and would imply coverage the app layer does not have.
    ]
)
