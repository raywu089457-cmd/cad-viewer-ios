import Foundation
import SwiftDXF
import DXFGeometry

// verify: a dependency-free harness that exercises the geometry core and the viewport
// arithmetic. The XCTest/Swift Testing suites in Tests/ are the canonical ones; this exists
// so the same logic can be checked on a machine without Xcode.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        failures += 1
        let extra = detail()
        print("FAIL  \(label)\(extra.isEmpty ? "" : " — \(extra)")")
    }
}

func nearly(_ a: Double, _ b: Double, _ epsilon: Double = 1e-9) -> Bool {
    abs(a - b) < epsilon
}

func section(_ name: String) {
    print("\n== \(name) ==")
}

// MARK: - DXF fixture

/// A minimal ASCII DXF with the given ENTITIES body.
func dxf(_ entities: String, extents: (Double, Double, Double, Double)? = nil) -> String {
    var header = """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1015
        """
    if let (minX, minY, maxX, maxY) = extents {
        header += """

            9
            $EXTMIN
            10
            \(minX)
            20
            \(minY)
            9
            $EXTMAX
            10
            \(maxX)
            20
            \(maxY)
            """
    }
    header += """

        0
        ENDSEC
        """
    return header + """

        0
        SECTION
        2
        ENTITIES
        \(entities)
        0
        ENDSEC
        0
        EOF
        """
}

func build(_ entities: String, extents: (Double, Double, Double, Double)? = nil) -> DrawScene? {
    guard let drawing = try? DXF.read(text: dxf(entities, extents: extents)) else { return nil }
    return SceneBuilder().build(drawing)
}

// MARK: - Primitives

section("LINE")
if let scene = build("""
    0
    LINE
    8
    Walls
    10
    0
    20
    0
    11
    10
    21
    5
    """) {
    check(scene.polylines.count == 1, "one polyline", "got \(scene.polylines.count)")
    if let line = scene.polylines.first {
        check(line.layer == "Walls", "layer name", line.layer)
        check(line.points.count == 2, "two points", "\(line.points.count)")
        check(line.points.first == Point(0, 0), "start point")
        check(line.points.last == Point(10, 5), "end point")
        check(!line.isClosed, "not closed")
    }
} else {
    check(false, "LINE fixture parses")
}

section("CIRCLE")
if let scene = build("""
    0
    CIRCLE
    8
    0
    10
    100
    20
    50
    40
    25
    """), let circle = scene.polylines.first
{
    check(circle.isClosed, "closed")
    check(circle.points.count >= 17, "enough segments", "\(circle.points.count)")
    let offRadius = circle.points.filter {
        !nearly((($0.x - 100) * ($0.x - 100) + ($0.y - 50) * ($0.y - 50)).squareRoot(), 25, 1e-7)
    }
    check(offRadius.isEmpty, "every point on the radius", "\(offRadius.count) off")
    if let first = circle.points.first, let last = circle.points.last {
        check(nearly(first.x, last.x, 1e-7) && nearly(first.y, last.y, 1e-7), "run closes")
    }
} else {
    check(false, "CIRCLE fixture parses")
}

section("ARC")
if let scene = build("""
    0
    ARC
    8
    0
    10
    0
    20
    0
    40
    10
    50
    0
    51
    90
    """), let arc = scene.polylines.first, let first = arc.points.first,
    let last = arc.points.last
{
    check(!arc.isClosed, "not closed")
    check(nearly(first.x, 10, 1e-6) && nearly(first.y, 0, 1e-6), "starts at 0 degrees")
    check(nearly(last.x, 0, 1e-6) && nearly(last.y, 10, 1e-6), "ends at 90 degrees")
    // A quarter turn should not come back through the far side.
    check(arc.points.allSatisfy { $0.x >= -1e-9 && $0.y >= -1e-9 }, "stays in the quadrant")
} else {
    check(false, "ARC fixture parses")
}

section("POLYLINE bulge")
if let scene = build("""
    0
    LWPOLYLINE
    8
    0
    90
    2
    70
    0
    10
    0
    20
    0
    42
    1
    10
    10
    20
    0
    """), let path = scene.polylines.first
{
    check(path.points.count > 4, "bulge expands to an arc", "\(path.points.count) points")
    // A positive bulge sweeps counter-clockwise; travelling +x, that puts the arc below the
    // chord, the way AutoCAD draws it.
    let lowest = path.points.map(\.y).min() ?? 0
    check(nearly(lowest, -5, 0.05), "semicircle dips to the radius", "\(lowest)")
    let highest = path.points.map(\.y).max() ?? 0
    check(highest < 0.01, "and stays on that side of the chord", "\(highest)")
} else {
    check(false, "LWPOLYLINE fixture parses")
}

section("TEXT")
if let scene = build("""
    0
    TEXT
    8
    Labels
    10
    20
    20
    30
    40
    20
    1
    Room 101
    """), let text = scene.texts.first
{
    check(text.string == "Room 101", "string", text.string)
    check(text.position == Point(20, 30), "position", "\(text.position)")
    check(text.height == 20, "height", "\(text.height)")
    check(text.layer == "Labels", "layer", text.layer)
} else {
    check(false, "TEXT fixture parses")
}

section("Layer colour inheritance")
do {
    let source = """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1015
        0
        ENDSEC
        0
        SECTION
        2
        TABLES
        0
        TABLE
        2
        LAYER
        0
        LAYER
        2
        Red
        70
        0
        62
        1
        6
        CONTINUOUS
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        Red
        10
        0
        20
        0
        11
        1
        21
        1
        0
        ENDSEC
        0
        EOF
        """
    if let drawing = try? DXF.read(text: source),
        let line = SceneBuilder().build(drawing).polylines.first
    {
        check(line.color.r > 0.9 && line.color.g < 0.1 && line.color.b < 0.1,
              "ByLayer resolves to red", "\(line.color)")
    } else {
        check(false, "layer fixture parses")
    }
}

section("Bounds")
if let scene = build("""
    0
    LINE
    10
    -5
    20
    -7
    11
    15
    21
    23
    """), let bounds = scene.bounds
{
    check(bounds.minX == -5 && bounds.minY == -7, "min corner")
    check(bounds.maxX == 15 && bounds.maxY == 23, "max corner")
} else {
    check(false, "bounds fixture parses")
}

section("Empty drawing")
if let scene = build("") {
    check(scene.polylines.isEmpty, "no polylines")
    check(scene.texts.isEmpty, "no text")
} else {
    check(false, "empty fixture parses")
}

// MARK: - ACI

section("ACI palette")
check(ACI.rgb(1) == RGB(1, 0, 0), "index 1 is red")
check(ACI.rgb(5) == RGB(0, 0, 1), "index 5 is blue")
check(nearly(ACI.rgb(8).r, 0.5), "index 8 is mid grey")
check(ACI.rgb(7, onDarkBackground: true) == RGB(1, 1, 1), "7 is white on dark")
check(ACI.rgb(7, onDarkBackground: false) == RGB(0, 0, 0), "7 is black on light")
do {
    var outOfRange = 0
    for index in 10...249 {
        let color = ACI.rgb(index)
        for component in [color.r, color.g, color.b] where component < 0 || component > 1 {
            outOfRange += 1
        }
    }
    check(outOfRange == 0, "generated colours stay in the cube", "\(outOfRange) bad")
    let distinct = Set((1...9).map { "\(ACI.rgb($0))" })
    check(distinct.count == 9, "the first nine differ", "\(distinct.count)")
}

// MARK: - Viewport

section("Viewport")
do {
    // Two points is too few for a percentile, so the extents are used as-is.
    let unitSquare = Bounds(minX: 0, minY: 0, maxX: 1000, maxY: 1000)
    if let plain = Viewport.fit(points: [Point(0, 0), Point(1000, 1000)], fallback: unitSquare) {
        check(plain.bounds == unitSquare, "frames the extents when there is nothing to judge")
        check(!plain.hasGeometryOutside, "nothing outside")
    } else {
        check(false, "viewport from two points")
    }

    // A drawing whose header swears the extents are a hundred times bigger than the
    // geometry: the header must not be trusted, or the drawing shows as a dot.
    var crowded: [Point] = []
    for i in 0..<200 { crowded.append(Point(Double(i) * 10, Double(i % 20) * 10)) }
    crowded.append(Point(1_000_000, 1_000_000))
    if let fitted = Viewport.fit(points: crowded, fallback: nil) {
        check(fitted.bounds.maxX < 100_000, "a far outlier is not framed",
              "maxX=(fitted.bounds.maxX)")
        check(fitted.hasGeometryOutside, "and the reader is told something is outside")
        check(fitted.expansionFactor > 1, "expansion factor > 1")
        // The content itself must still be inside the frame.
        check(fitted.bounds.minX <= 0 && fitted.bounds.maxX >= 1990,
              "but the content is inside it")
    } else {
        check(false, "viewport with an outlier")
    }

    // A drawing with no outliers is shown in full: cropping a real edge is worse.
    var tidy: [Point] = []
    for i in 0..<100 { tidy.append(Point(Double(i), Double(i % 10))) }
    if let fitted = Viewport.fit(points: tidy, fallback: nil) {
        check(!fitted.hasGeometryOutside, "a tidy drawing is not cropped")
    } else {
        check(false, "viewport for a tidy drawing")
    }
}

section("View transform")
let portrait = ScreenSize(width: 390, height: 844)
// A 1000-unit square, the reference drawing the transform tests fit.
let square = Bounds(minX: 0, minY: 0, maxX: 1000, maxY: 1000)

let fitted = ViewTransform.fitting(square, in: portrait)
check(fitted.scale.isFinite && fitted.scale > 0, "fit scale is sane", "\(fitted.scale)")
do {
    var outside = 0
    for corner in [Point(0, 0), Point(1000, 0), Point(0, 1000), Point(1000, 1000)] {
        let screen = fitted.screenPoint(for: corner)
        if screen.x < -0.001 || screen.x > portrait.width + 0.001
            || screen.y < -0.001 || screen.y > portrait.height + 0.001
        {
            outside += 1
        }
    }
    check(outside == 0, "all four corners are on screen", "\(outside) outside")
}
do {
    let middle = fitted.screenPoint(for: Point(500, 500))
    check(nearly(middle.x, portrait.width / 2, 1e-6), "centred horizontally")
    check(nearly(middle.y, portrait.height / 2, 1e-6), "centred vertically")
}
do {
    var drift = 0.0
    for screen in [
        ScreenPoint(x: 0, y: 0), ScreenPoint(x: 195, y: 422), ScreenPoint(x: 390, y: 844)
    ] {
        let back = fitted.screenPoint(for: fitted.drawingPoint(at: screen))
        drift = max(drift, abs(back.x - screen.x), abs(back.y - screen.y))
    }
    check(drift < 1e-9, "screen/drawing round-trip", "\(drift)")
}

do {
    var transform = fitted
    let anchor = ScreenPoint(x: 120, y: 700)
    let before = transform.drawingPoint(at: anchor)
    transform.zoom(by: 3, around: anchor)
    let after = transform.drawingPoint(at: anchor)
    check(nearly(before.x, after.x, 1e-6) && nearly(before.y, after.y, 1e-6),
          "zoom keeps the anchor under the finger")
}
do {
    var transform = fitted
    let anchor = ScreenPoint(x: 300, y: 200)
    transform.zoom(by: 2.5, around: anchor)
    transform.zoom(by: 1 / 2.5, around: anchor)
    check(nearly(transform.scale, fitted.scale, 1e-9), "zoom is reversible (scale)")
    check(nearly(transform.center.x, fitted.center.x, 1e-6), "zoom is reversible (x)")
    check(nearly(transform.center.y, fitted.center.y, 1e-6), "zoom is reversible (y)")
}
do {
    var transform = fitted
    let start = transform.screenPoint(for: Point(0, 0))
    transform.pan(by: ScreenPoint(x: 50, y: 50))
    let moved = transform.screenPoint(for: Point(0, 0))
    check(nearly(moved.x, start.x + 50, 1e-6), "pan follows the finger (x)")
    check(nearly(moved.y, start.y + 50, 1e-6), "pan follows the finger (y)")
}
do {
    var transform = fitted
    let anchor = ScreenPoint(x: 195, y: 422)
    for _ in 0..<200 { transform.zoom(by: 2, around: anchor) }
    let mostZoomedIn = transform.scale
    check(mostZoomedIn.isFinite && mostZoomedIn > 0, "zoom in stays finite")
    for _ in 0..<600 { transform.zoom(by: 0.5, around: anchor) }
    check(transform.scale.isFinite && transform.scale > 0, "zoom out stays finite")
    // Scale is points per drawing unit, so zooming out makes it smaller.
    check(transform.scale < mostZoomedIn, "zoom out moves the other way")
}
do {
    var transform = fitted
    let center = transform.center
    transform.resize(to: ScreenSize(width: 844, height: 390))
    check(transform.center == center, "resize keeps the centre")
    check(transform.viewSize.width == 844, "resize stores the size")
}
do {
    var transform = fitted
    // Zoom into the middle of the drawing, which keeps that part in view.
    transform.zoom(
        by: 20, around: ScreenPoint(x: portrait.width / 2, y: portrait.height / 2))
    check(transform.isVisible(Bounds(minX: 490, minY: 490, maxX: 510, maxY: 510)),
          "the zoomed-in centre is visible")
    check(!transform.isVisible(Bounds(minX: 0, minY: 0, maxX: 10, maxY: 10)),
          "a far corner is culled")
}
do {
    let point = Bounds(minX: 5, minY: 5, maxX: 5, maxY: 5)
    let transform = ViewTransform.fitting(point, in: portrait)
    check(transform.scale.isFinite && transform.scale > 0, "single point fits")
    check(transform.center == Point(5, 5), "single point centres on itself")

    let zero = ViewTransform.fitting(square, in: ScreenSize(width: 0, height: 0))
    check(zero.scale.isFinite && zero.scale > 0, "zero-size view does not divide by zero")
}

// MARK: - File routing

section("DrawingKind")
check(DrawingKind(fileName: "plan.dxf") == .dxf, "dxf")
check(DrawingKind(fileName: "PLAN.DXF") == .dxf, "dxf upper")
check(DrawingKind(fileName: "site.dwg") == .dwg, "dwg")
check(DrawingKind(fileName: "Site.DWG") == .dwg, "dwg mixed")
check(DrawingKind(fileName: "sheet.pdf") == .pdf, "pdf")
check(DrawingKind(fileName: "floor.plan.v2.dxf") == .dxf, "dotted name uses the last part")
check(DrawingKind(fileName: "report.final.pdf") == .pdf, "dotted pdf")
check(DrawingKind(fileName: "notes.txt") == .unsupported(extension: "txt"), "txt rejected")
check(DrawingKind(fileName: "README") == .unsupported(extension: ""), "no extension")
check(!DrawingKind(fileName: "notes.txt").canRender, "txt cannot be rendered")
check(!DrawingKind(fileName: "README").canRender, "no extension cannot be rendered")
check(DrawingKind(fileName: "a.dxf").canRender, "dxf can be rendered")
check(DrawingKind(fileName: "a.dwg").canRender, "dwg can be rendered")
check(DrawingKind(fileName: "a.pdf").canRender, "pdf can be rendered")
check(DrawingKind(fileName: "a.dxf").fileExtension == "dxf", "dxf extension")
// Foundation treats a leading dot as the start of the name, not of an extension, so
// ".dxf" has no extension. The app therefore refuses it rather than guessing.
check(DrawingKind(fileName: ".dxf") == .unsupported(extension: ""), "a dotfile has no extension")
check(DrawingKind(fileName: "trailing.") == .unsupported(extension: ""), "trailing dot")

section("LoadFailure messages")
do {
    let unsupported = LoadFailure(fileName: "a.step", reason: .unsupportedType("step"))
    check(unsupported.message == ".step files cannot be shown here.", "names the extension", unsupported.message)
    check(unsupported.title == "Could not open a.step", "title names the file", unsupported.title)

    let noExtension = LoadFailure(fileName: "README", reason: .unsupportedType(""))
    check(noExtension.message.contains("no extension"), "explains a missing extension", noExtension.message)

    let empty = LoadFailure(fileName: "a.dxf", reason: .empty)
    check(empty.message == "The file is empty.", "empty message")

    let binary = LoadFailure(fileName: "a.dxf", reason: .binaryDXF)
    check(binary.message.contains("binary DXF"), "binary message says what to do", binary.message)

    let nothing = LoadFailure(fileName: "a.dxf", reason: .noGeometry)
    check(nothing.message.contains("no model-space geometry"), "no-geometry message", nothing.message)

    let detail = LoadFailure(fileName: "a.dxf", reason: .unreadable("bad group code"))
    check(detail.message == "bad group code", "an unreadable message passes the detail through", detail.message)

    let anonymous = LoadFailure(fileName: "", reason: .empty)
    check(anonymous.title == "Could not open the file", "title without a name", anonymous.title)

    // Two failures are distinct objects even when they describe the same thing, so a
    // repeated error still re-presents its alert.
    let a = LoadFailure(fileName: "a.dxf", reason: .empty)
    let b = LoadFailure(fileName: "a.dxf", reason: .empty)
    check(a.id != b.id, "each failure has its own identity")
    check(a.reason == b.reason, "the reason itself compares equal")
}

// MARK: - Bundle serving

section("Bundle serving: the drawing endpoint")
check(BundleServing.isDrawingRequest(path: "/__dwg__"), "exact path")
check(BundleServing.isDrawingRequest(path: "/anything/__dwg__"), "suffix path")
check(!BundleServing.isDrawingRequest(path: "/index.html"), "a file is not the drawing")
check(!BundleServing.isDrawingRequest(path: "/__dwg__/x"), "a suffix is not enough")

section("Bundle serving: path escape")
do {
    let root = URL(fileURLWithPath: "/app/dwgviewer")

    let index = BundleServing.relativeFile(for: "/index.html", root: root)
    check(index?.lastPathComponent == "index.html", "a normal file resolves")
    check(index?.path.hasPrefix("/app/dwgviewer/") == true, "and stays inside the bundle")

    // An empty path means the site root.
    check(BundleServing.relativeFile(for: "/", root: root)?.lastPathComponent == "index.html",
          "root maps to index.html")
    check(BundleServing.relativeFile(for: "", root: root)?.lastPathComponent == "index.html",
          "empty maps to index.html")

    // The one that matters: nothing may leave the bundle.
    check(BundleServing.relativeFile(for: "/../secrets.txt", root: root) == nil,
          "a relative escape is refused")
    check(BundleServing.relativeFile(for: "/../../etc/passwd", root: root) == nil,
          "a deeper escape is refused")
    check(BundleServing.relativeFile(for: "/assets/../../secrets", root: root) == nil,
          "an escape hidden mid-path is refused")

    // A sibling directory that merely shares a string prefix is not inside the bundle.
    let siblingRoot = URL(fileURLWithPath: "/app/dwg")
    check(BundleServing.relativeFile(for: "/../dwgviewer/index.html", root: siblingRoot) == nil,
          "a prefix-sharing sibling is refused")

    check(BundleServing.relativeFile(for: "/assets/app.js", root: root)?.path.hasSuffix("assets/app.js") == true,
          "a nested file resolves")
}

section("Bundle serving: MIME types")
do {
    check(BundleServing.mimeType(forExtension: "wasm") == "application/wasm",
          "wasm must be application/wasm for streaming instantiation",
          BundleServing.mimeType(forExtension: "wasm"))
    check(BundleServing.mimeType(forExtension: "JS").hasPrefix("text/javascript"),
          "js is javascript, case-insensitively",
          BundleServing.mimeType(forExtension: "JS"))
    check(BundleServing.mimeType(forExtension: "mjs").hasPrefix("text/javascript"), "mjs too")
    check(BundleServing.mimeType(forExtension: "html").hasPrefix("text/html"), "html")
    check(BundleServing.mimeType(forExtension: "css").hasPrefix("text/css"), "css")
    check(BundleServing.mimeType(forExtension: "somethingelse") == "application/octet-stream",
          "unknown types are octets")
}

section("Bundle serving: headers")
do {
    let headers = BundleServing.headers(mime: "application/wasm", byteCount: 1234)
    check(headers["Content-Type"] == "application/wasm", "content type")
    check(headers["Content-Length"] == "1234", "content length is the byte count")
    check(headers["Cache-Control"] == "no-store", "never cached")
    check(headers["Cross-Origin-Embedder-Policy"] == "require-corp",
          "the policy the wasm worker needs", headers["Cross-Origin-Embedder-Policy"] ?? "missing")
}

// MARK: - Viewer events

section("Viewer events: decoding")
do {
    check(ViewerEvent(message: ["event": "ready"]) == .ready, "ready")
    check(ViewerEvent(message: ["event": "loading"]) == .loading, "loading")
    check(ViewerEvent(message: ["event": "activated"]) == .activated, "activated")
    check(ViewerEvent(message: ["event": "rendered", "ms": 120]) == .rendered(milliseconds: 120),
          "rendered with a timing")
    check(ViewerEvent(message: ["event": "rendered"]) == .rendered(milliseconds: nil),
          "rendered without a timing")
    check(ViewerEvent(message: ["event": "error", "message": "wasm missing"]) == .failed("wasm missing"),
          "error carries its message")

    // The page may grow events the app does not act on; they must not break a drawing.
    check(ViewerEvent(message: ["event": "somethingNew"]) == .ignored, "unknown is ignored")
    check(ViewerEvent(message: [:]) == .ignored, "no event is ignored")

    // An error with no message is still an error worth showing.
    if case .failed(let text) = ViewerEvent(message: ["event": "error"]) {
        check(!text.isEmpty, "an error without a message still says something")
    } else {
        check(false, "a bare error decodes as a failure")
    }
    if case .failed(let text) = ViewerEvent(message: ["event": "error", "message": ""]) {
        check(!text.isEmpty, "an empty message still says something")
    } else {
        check(false, "an empty message decodes as a failure")
    }
}

section("Viewer events: what the UI does")
do {
    // The two that must show progress, and the four that must not: a spinner left on top of
    // an open drawing is the bug this rule prevents.
    check(ViewerEvent.ready.statusText != nil, "ready shows progress")
    check(ViewerEvent.loading.statusText != nil, "loading shows progress")
    check(ViewerEvent.activated.statusText == nil, "activated clears the overlay")
    check(ViewerEvent.rendered(milliseconds: 1).statusText == nil, "rendered clears the overlay")
    check(ViewerEvent.failed("x").statusText == nil, "a failure clears the overlay")
    check(ViewerEvent.ignored.statusText == nil, "an ignored event changes nothing")

    // The engine is warm once it has reported ready or drawn something, which is what lets
    // the next drawing reuse the page instead of paying for a reload.
    check(ViewerEvent.ready.engineIsWarm, "ready warms the engine")
    check(ViewerEvent.activated.engineIsWarm, "activated means the engine works")
    check(ViewerEvent.rendered(milliseconds: nil).engineIsWarm, "rendered means it works")
    check(!ViewerEvent.loading.engineIsWarm, "loading alone does not")
    check(!ViewerEvent.failed("x").engineIsWarm, "a failure does not")

    check(ViewerEvent.failed("boom").errorMessage == "boom", "an error surfaces")
    check(ViewerEvent.ready.errorMessage == nil, "ready is not an error")
    check(ViewerEvent.activated.errorMessage == nil, "activated is not an error")
}

section("Primitive bounds (the renderer's culling)")
do {
    if let scene = build("""
        0
        LINE
        10
        -5
        20
        -7
        11
        15
        21
        23
        """), let line = scene.polylines.first {
        check(line.bounds.minX == -5 && line.bounds.maxX == 15, "polyline bounds x")
        check(line.bounds.minY == -7 && line.bounds.maxY == 23, "polyline bounds y")
    } else {
        check(false, "line bounds fixture")
    }

    // A circle's points are on the circumference; its bounds must be its box.
    if let scene = build("""
        0
        CIRCLE
        10
        100
        20
        50
        40
        25
        """), let circle = scene.polylines.first {
        check(circle.bounds.minX >= 75 - 1e-9 && circle.bounds.minX <= 75 + 1e-9,
              "circle bounds left", "(circle.bounds.minX)")
        check(circle.bounds.maxX <= 125 + 1e-9 && circle.bounds.maxX >= 125 - 1e-9,
              "circle bounds right", "(circle.bounds.maxX)")
    } else {
        check(false, "circle bounds fixture")
    }

    if let scene = build("""
        0
        SOLID
        10
        0
        20
        0
        11
        10
        21
        0
        12
        0
        22
        10
        13
        10
        23
        10
        """), let fill = scene.fills.first {
        check(fill.bounds.minX == 0 && fill.bounds.maxX == 10, "fill bounds x")
        check(fill.bounds.minY == 0 && fill.bounds.maxY == 10, "fill bounds y")
    } else {
        check(false, "fill bounds fixture")
    }
}

// MARK: - Result

print("")
if failures == 0 {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAILED — \(failures) of \(checks) checks")
    exit(1)
}
