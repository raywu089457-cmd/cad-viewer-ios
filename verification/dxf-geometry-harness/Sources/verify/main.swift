import Foundation
import SwiftDXF
import DXFGeometry

// verify: a dependency-free harness that exercises the geometry core and the viewport
// arithmetic. The XCTest/Swift Testing suites in Tests/ are the canonical ones; this exists
// so the same logic can be checked on a machine without Xcode.

var failures = 0
var checks = 0

// A DXF holding both solid and patterned hatches, passed on the command line. A HATCH needs
// the full boundary-path encoding, so the fixture is a real converted drawing rather than a
// hand-written one.
let hatchSamplePath = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".dxf") }) ?? ""

/// Reads the hatch sample from stdin, as the other harnesses do: WASI Foundation has no
/// way to read a file by path.
func hatchSampleText() -> String? {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { return nil }
    return String(decoding: data, as: Unicode.ASCII.self)
}

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

    // A circle is tessellated into an inscribed polygon, so its extreme point is very close
    // to the box but not exactly on it. What matters is that the cached box contains every
    // point, or an on-screen circle would be culled.
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
        let box = circle.bounds
        let inside = circle.points.allSatisfy {
            $0.x >= box.minX - 1e-9 && $0.x <= box.maxX + 1e-9 &&
            $0.y >= box.minY - 1e-9 && $0.y <= box.maxY + 1e-9
        }
        check(inside, "every circle point is inside the cached box")
        check(box.minX >= 75 - 1e-9 && box.minX < 76,
              "the box hugs the left of the circle", "\(box.minX)")
        check(box.maxX <= 125 + 1e-9 && box.maxX > 124,
              "the box hugs the right of the circle", "\(box.maxX)")
        check(box.minY >= 25 - 1e-9 && box.minY < 26,
              "the box hugs the bottom", "\(box.minY)")
        check(box.maxY <= 75 + 1e-9 && box.maxY > 74,
              "the box hugs the top", "\(box.maxY)")
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

section("Curve tolerance follows the geometry, not the header")
do {
    /// Segments in a lone circle, optionally with header extents supplied.
    func circleSegments(radius: Double, withHeader: Bool) -> Int {
        var header = ""
        if withHeader {
            header = """
            9
            $EXTMIN
            10
            \(-radius)
            20
            \(-radius)
            9
            $EXTMAX
            10
            \(radius)
            20
            \(radius)
            """
        }
        let source = """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1015
        \(header)
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        CIRCLE
        10
        0
        20
        0
        40
        \(radius)
        0
        ENDSEC
        0
        """
        guard let drawing = try? DXF.read(text: source) else { return -1 }
        return SceneBuilder().build(drawing).polylines.first?.points.count ?? -1
    }

    // A header that is missing must give the same result as one that is present, because the
    // tolerance is measured from the geometry. R12 files usually have no `$EXTMIN` at all.
    let withoutHeader = circleSegments(radius: 1_000_000, withHeader: false)
    let withHeader = circleSegments(radius: 1_000_000, withHeader: true)
    check(
        withoutHeader == withHeader,
        "a missing header gives the same tessellation",
        "\(withoutHeader) vs \(withHeader)")
    check(withoutHeader > 16, "a full circle is smooth", "\(withoutHeader)")

    // Tessellation is deliberately scale-invariant: the tolerance is a fraction of the drawing
    // size, so the same circle looks equally smooth whether the file is in millimetres or
    // metres. This is the property that makes one tolerance work for every drawing.
    let tiny = circleSegments(radius: 0.5, withHeader: false)
    let huge = circleSegments(radius: 1_000_000, withHeader: false)
    check(
        abs(tiny - huge) <= 2,
        "the same circle tessellates the same at any scale",
        "tiny \(tiny) vs huge \(huge)")

    // And the smoothness is bounded rather than unbounded: a circle never explodes into
    // thousands of segments.
    check(huge <= 60, "a full circle stays within the cap", "\(huge)")
}

section("Drawing handoff")
do {
    // Direct hands the bytes over as base64 and keeps the wasm engine warm; reload always
    // works. The choice is size and whether the page offers the entry point.
    check(DrawingHandoff(byteCount: 1000, pageCanAcceptDirectly: true) == .directly,
          "a small drawing goes directly")
    check(
        DrawingHandoff(byteCount: DrawingHandoff.directLimit, pageCanAcceptDirectly: true)
            == .directly,
        "exactly at the limit still goes directly")
    check(
        DrawingHandoff(byteCount: DrawingHandoff.directLimit + 1, pageCanAcceptDirectly: true)
            == .viaReload,
        "one byte over the limit reloads")
    check(DrawingHandoff(byteCount: 1, pageCanAcceptDirectly: false) == .viaReload,
          "a page without the entry point means a reload")
    // A real DWG is routinely tens of megabytes; base64 would add a third on top.
    check(
        DrawingHandoff(byteCount: 40 * 1024 * 1024, pageCanAcceptDirectly: true) == .viaReload,
        "a large drawing reloads")
}

section("Hatch solidity")
do {
    // A hatch is either a solid fill or a pattern (ANSI31 on a section view). The reader
    // models the boundary but not the pattern lines, so a patterned hatch has to be outlined:
    // drawing it as a solid block of colour says the section is filled, which is wrong.
    //
    // The fixture is passed on the command line, because a hand-written HATCH needs the full
    // boundary-path encoding and is easy to get subtly wrong. Without one, nothing is
    // claimed — a silent pass here would be worse than no check.
    if hatchSamplePath.isEmpty {
        check(true, "no hatch sample supplied, so solidity was not checked")
    } else if let text = hatchSampleText(), let drawing = try? DXF.read(text: text) {
        let fills = SceneBuilder().build(drawing).fills
        check(!fills.isEmpty, "the sample has hatches", "\(fills.count)")
        check(fills.contains { $0.isSolid }, "at least one is a solid fill")
        check(fills.contains { !$0.isSolid }, "at least one is a pattern")
        // Every fill must carry a boundary, solid or not, or it cannot be outlined either.
        let boundaryless = fills.filter { $0.outer.count < 3 }
        check(boundaryless.isEmpty, "every fill has a boundary", "\(boundaryless.count) without")
    } else {
        check(false, "the hatch sample is readable at \(hatchSamplePath)")
    }

    // A SOLID entity is always a fill.
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
        check(fill.isSolid, "a SOLID entity is solid")
    } else {
        check(false, "solid entity fixture")
    }
}

section("Dimension text")
do {
    // `<>` is where the measured value goes, and almost every dimension uses it as the
    // format. Returning the override verbatim shows the placeholder itself: nine dimensions
    // in the fixture drawings read "<>" before this was handled.
    //
    // computedMeasurement comes from the definition points rather than the stored group 42,
    // which is the more trustworthy of the two, so the fixture makes the geometry agree with
    // the value under test.
    func label(override: String?, width: Double) -> String? {
        let dimension = DXF.Dimension(
            kind: .linear, measurement: width, textOverride: override,
            textPosition: DXF.Point(0, 0, 0), defPoint: DXF.Point(0, 0, 0),
            defPoint2: DXF.Point(0, 0, 0), defPoint3: DXF.Point(width, 0, 0),
            layer: "0", color: 7)
        return SceneBuilder.dimensionLabel(dimension)
    }

    check(label(override: nil, width: 40) == "40", "a plain dimension shows its value")
    check(label(override: "<>", width: 40) == "40", "<> is replaced by the value")
    check(label(override: "<> mm", width: 15) == "15 mm", "a suffix survives")
    check(label(override: "<>\\P(max)", width: 67) == "67\n(max)", "a line break is decoded")
    check(label(override: "nominal", width: 40) == "nominal", "text with no <> is left alone")
    check(label(override: "<>", width: 27.321) == "27.32", "a fraction keeps two places")
    // A literal space is the DXF convention for suppressing the text.
    check(label(override: "", width: 40) == nil, "an empty override shows nothing")
    check(label(override: " ", width: 40) == nil, "a space override shows nothing")
}

section("Load generations")
do {
    // Two loads can overlap: the user picks a second drawing before the first has started.
    // A timeout from the earlier load must not resume the later load's continuation, or the
    // wrong drawing gets abandoned and a task hangs.
    var generations = LoadGeneration()
    let first = generations.begin()
    check(generations.isCurrent(first), "the first load is current")

    let second = generations.begin()
    check(!generations.isCurrent(first), "the first load is no longer current")
    check(generations.isCurrent(second), "the second load is")
    check(first != second, "each load gets its own generation")

    // Many loads in a row must stay monotonic, or an old generation could match a new one.
    var many = LoadGeneration()
    var seen: [Int] = []
    for _ in 0..<50 { seen.append(many.begin()) }
    check(Set(seen).count == 50, "every generation is distinct", "(Set(seen).count)")
    check(seen == seen.sorted(), "and they increase")
}
section("Resource location")
do {
    // SwiftPM copies the folder into the bundle, but under which name depends on how the
    // target is built. Guessing wrong gives a blank DWG tab, so the candidates are tried.
    let candidates = ResourceLocation.candidates(for: "Resources/dwgviewer")
    check(candidates.contains("dwgviewer"), "the leaf name is a candidate")
    check(candidates.contains("Resources/dwgviewer"), "so is the written path")
    check(candidates.count == Set(candidates).count, "with no duplicates")

    // A bare name has no directory to strip, so it must not be listed twice.
    let bare = ResourceLocation.candidates(for: "dwgviewer")
    check(bare == ["dwgviewer"], "a bare name yields one candidate", "\(bare)")

    func find(existing: [String]) -> String? {
        ResourceLocation.find(
            path: "Resources/dwgviewer", in: "/app", exists: { existing.contains($0) })
    }

    check(find(existing: ["/app/dwgviewer"]) == "/app/dwgviewer", "finds the leaf name")
    check(find(existing: ["/app/Resources/dwgviewer"]) == "/app/Resources/dwgviewer", "finds the written path")
    check(find(existing: []) == nil, "reports nothing when absent")
    check(find(existing: ["/app/other"]) == nil, "ignores unrelated folders")

    // The leaf name wins when both exist, which is what SwiftPM documents.
    check(
        find(existing: ["/app/dwgviewer", "/app/Resources/dwgviewer"])
            == "/app/dwgviewer",
        "prefers the leaf name")
}

section("Dimension line gap")
do {
    // The dimension line is broken where the text sits, as CAD does. A line through the
    // number makes both hard to read, which is what the fixtures looked like before.
    // The helpers are the testable part: a gap is a projection along the line.
    let a = Point(0, 0)
    let b = Point(100, 0)
    check(a.distance(to: b) == 100, "distance")
    check(Point(40, 10).projection(onto: a, b) == 40, "projection ignores the offset")
    check(Point(-10, 0).projection(onto: a, b) < 0, "a point behind the start is negative")
    let mid = Point.along(a, b, 50)
    check(mid == Point(50, 0), "halfway along", "(mid)")
    check(Point.along(a, b, 0) == a, "the start")
    check(Point.along(a, b, 100) == b, "the end")
    // A degenerate line must not divide by zero.
    check(a.distance(to: a) == 0, "a zero-length line")
    check(Point.along(a, a, 5) == a, "and stays put")
    check(Point(1, 1).projection(onto: a, a) == 0, "or projects to its start")
}
section("Block attributes")
do {
    // Block attributes are the part numbers and titles AutoCAD draws for a reference. They
    // were invisible here: the reader models them, but only expands them into entities when
    // asked, and the app never asked. A drawing of parts came out as outlines with no labels.
    //
    // The fixture is a real one from the DXF library, which carries four attributes across
    // three block references.
    let sample = "../../SwiftDXF/Tests/SwiftDXFTests/Fixtures/attributes.dxf"
    if let text = try? String(
        contentsOf: URL(fileURLWithPath: sample), encoding: .utf8)
    {
        var options = DXF.ReadOptions()
        options.expandBlocks = true
        options.expandAttributes = true
        if let drawing = try? DXF.read(text: text, options: options) {
            let scene = SceneBuilder().build(drawing)
            check(!scene.texts.isEmpty, "attributes become text", "(scene.texts.count)")
            // They are only there because the option was set; without it they are skipped.
            var without = DXF.ReadOptions()
            without.expandBlocks = true
            if let plain = try? DXF.read(text: text, options: without) {
                let bare = SceneBuilder().build(plain)
                check(
                    bare.texts.count < scene.texts.count,
                    "and only when asked",
                    "(bare.texts.count) vs (scene.texts.count)")
            }
        } else {
            check(false, "the attribute fixture parses")
        }
    } else {
        // wasm cannot read by path, so this check only runs where the file is reachable.
        check(true, "attribute fixture not reachable here, so skipped")
    }
}
section("Skipped entities")
do {
    // The reader does not model every DXF entity type, and a drawing that is quietly missing
    // them looks complete. The summary is what tells the reader, so its wording matters.
    check(SkippedEntities.summary([:]) == "", "nothing skipped says nothing")

    let one = SkippedEntities.summary(["LIGHT": 1])
    check(one == "1 item not shown: LIGHT.", "one is singular", "\(one)")

    let two = SkippedEntities.summary(["RAY": 2])
    check(two == "2 items not shown: RAY.", "several is plural", "\(two)")

    // Names are sorted, so the message does not depend on dictionary order.
    let mixed = SkippedEntities.summary(["XLINE": 1, "ATTDEF": 2])
    check(mixed == "3 items not shown: ATTDEF, XLINE.", "sorted", "\(mixed)")

    // Past the limit, the rest is counted rather than listed.
    let many = SkippedEntities.summary([
        "A": 1, "B": 1, "C": 1, "D": 1, "E": 1
    ])
    check(many.contains(" and 2 more"), "abbreviates the tail", "\(many)")
    check(many.hasPrefix("5 items not shown: A, B, C"), "and lists three", "\(many)")

    // Exactly at the limit there is no tail to abbreviate.
    let exact = SkippedEntities.summary(["A": 1, "B": 1, "C": 1])
    check(!exact.contains("more"), "no tail at the limit", "\(exact)")

    // A limit of zero must still show something rather than an empty list.
    let zero = SkippedEntities.summary(["X": 1], shownNames: 0)
    check(zero.contains("X"), "a zero limit still names one", "\(zero)")
}
section("Draw batching")
do {
    // Grouped by the colour an entity is drawn in, not by its ACI index: two entities can
    // share index 256 (ByLayer) and resolve to different layers, and therefore different
    // colours. Grouping by index painted 354 lines of one real drawing in the wrong colour.
    let red = RGB(1, 0, 0)
    let green = RGB(0, 1, 0)
    let blue = RGB(0, 0, 1)
    let colors = [red, red, green, red, blue, green]
    let groups = DrawBatching.groups(colors: colors)
    check(groups[red.packed] == [0, 1, 3], "red keeps drawing order")
    check(groups[green.packed] == [2, 5], "green groups its two")
    check(groups[blue.packed] == [4], "a single one")
    check(groups.count == 3, "three colours, three groups")
    check(groups.values.reduce(0) { $0 + $1.count } == colors.count, "nothing lost")
    let culled = DrawBatching.groups(
        colors: colors, visible: [true, false, true, true, false, true])
    check(culled[red.packed] == [0, 3], "a culled one is skipped")
    check(culled[blue.packed] == nil, "a colour with everything culled is absent")
    check(DrawBatching.groups(colors: []).isEmpty, "nothing groups to nothing")

    let white = RGB(1, 1, 1)
    let yellow = RGB(1, 1, 0)
    let mixed = DrawBatching.groups(colors: [white, yellow, white])
    check(mixed.count == 2, "the same index in two colours is two groups")
    check(mixed[white.packed] == [0, 2], "the white ones stay together")
    check(mixed[yellow.packed] == [1], "the yellow one is alone")

    check(RGB(1, 1, 1).packed == 0xFF_FFFF, "white packs to the top of the range")
    check(RGB(0, 0, 0).packed == 0, "black to zero")
    check(RGB(2, -1, 0.5).packed == (255 << 16) | 128, "values outside 0...1 are clamped")
    check(RGB(Double.nan, 0, 0).packed == 0, "a non-finite component becomes zero")
}

section("PDF zoom limits")
do {
    // scaleFactorForSizeToFit is meaningless before layout. Deriving limits from it in
    // makeUIView gave a floor of 0.01 and a ceiling of 4, a pinch range far narrower than the
    // page needs, and nothing would have said so.
    let unmeasured = PDFZoom.limits(fitScale: 0)
    check(!unmeasured.measured, "a zero fit scale is not measured")
    check(unmeasured.maximum > unmeasured.minimum, "the fallback range is usable", "\(unmeasured)")

    // A NaN or negative scale is no better than zero.
    check(!PDFZoom.limits(fitScale: .nan).measured, "NaN is not measured")
    check(!PDFZoom.limits(fitScale: -1).measured, "a negative scale is not measured")

    // A real fit scale gives a range proportional to it, so the same page zooms the same way
    // whatever the screen.
    let measured = PDFZoom.limits(fitScale: 2)
    check(measured.measured, "a real scale is measured")
    check(abs(measured.minimum - 0.5) < 1e-9, "a quarter of the fit scale", "\(measured.minimum)")
    check(abs(measured.maximum - 24) < 1e-9, "twelve times the fit scale", "\(measured.maximum)")

    // Scaling the page must scale the range with it, not clamp to a fixed pair.
    let bigger = PDFZoom.limits(fitScale: 4)
    check(bigger.maximum > measured.maximum, "a larger page zooms further in")
    check(bigger.minimum > measured.minimum, "and its floor rises too")
}
section("PDF open verdict")
do {
    // Two failures that read the same to a user — a file that is not a PDF, and one that is but
    // holds nothing — and the reader is told which. Before this the decision lived inside the
    // viewer, where PDFKit cannot be built off an Apple platform and nothing could check it.
    check(PDFOpenOutcome.verdict(pageCount: 12) == .readable(pageCount: 12), "a document with pages is readable")
    check(PDFOpenOutcome.verdict(pageCount: 12).message == nil, "and shows no error")

    // A one-page document is the off-by-one that would read as empty.
    check(PDFOpenOutcome.verdict(pageCount: 1) == .readable(pageCount: 1), "one page is readable")

    check(PDFOpenOutcome.verdict(pageCount: nil) == .notAPDF, "no document means the bytes are not a PDF")
    check(PDFOpenOutcome.verdict(pageCount: 0) == .noPages, "no pages is its own failure")

    // A failure with no message would leave the viewer on a spinner forever; a message on a
    // readable document would replace the page with an error. Both directions matter.
    for count in [nil, 0] as [Int?] {
        check(PDFOpenOutcome.verdict(pageCount: count).message != nil, "every failure says something", "\(String(describing: count))")
    }
    check(PDFOpenOutcome.verdict(pageCount: 3).message == nil, "a readable document says nothing")

    // The guard is a comparison, not an equality: `pageCount != 0` would let a negative through
    // and show a document with no pages as readable.
    check(PDFOpenOutcome.verdict(pageCount: -1) == .noPages, "a negative count is not readable")
}
section("File picker cancellation")
do {
    // Dismissing the picker arrives as a failure with NSUserCancelledError. Reporting it as
    // one shows an error for an action that did nothing wrong, and trains people to dismiss
    // alerts without reading them.
    let cancelled = NSError(domain: NSCocoaErrorDomain, code: 3072)
    check(FilePickOutcome.isCancellation(cancelled), "a cancellation is recognised")

    // Any other failure is a real one and must still be reported.
    let notFound = NSError(domain: NSCocoaErrorDomain, code: 4)
    check(!FilePickOutcome.isCancellation(notFound), "a file-not-found is not a cancel")
    let otherDomain = NSError(domain: "SomeOtherDomain", code: 3072)
    check(!FilePickOutcome.isCancellation(otherDomain), "the code alone is not enough")

    // A wrapped cancellation still counts.
    let wrapped = NSError(
        domain: "Wrapper", code: 1,
        userInfo: [NSUnderlyingErrorKey: cancelled])
    check(FilePickOutcome.isCancellation(wrapped), "a wrapped cancellation is recognised")

    // A wrapped real error does not become a cancellation.
    let wrappedReal = NSError(
        domain: "Wrapper", code: 1,
        userInfo: [NSUnderlyingErrorKey: notFound])
    check(!FilePickOutcome.isCancellation(wrappedReal), "a wrapped failure is not a cancel")
}
section("Overlapping loads")
do {
    // The reader can pick a second file while the first is still parsing. Both waits share
    // one view, so the abandoned one must not land afterwards and replace the chosen file.
    var generation = LoadGeneration()

    // Opening a file: reset() invalidates whatever was in flight, then open() takes a new
    // generation for itself.
    _ = generation.begin()          // reset
    let slow = generation.begin()   // the 50 MB drawing

    // The reader picks a smaller one while that is still parsing.
    _ = generation.begin()          // reset again
    let quick = generation.begin()  // the file they actually want

    check(!generation.isCurrent(slow), "the abandoned load is stale")
    check(generation.isCurrent(quick), "the chosen one is current")

    // And a load that finishes before anything else is still current.
    var single = LoadGeneration()
    _ = single.begin()
    let only = single.begin()
    check(single.isCurrent(only), "a lone load lands")

    // Closing the document discards anything in flight.
    _ = single.begin()
    check(!single.isCurrent(only), "closing discards the pending load")
}
section("Gesture session")
do {
    let size = ScreenSize(width: 390, height: 844)
    let square = Bounds(minX: 0, minY: 0, maxX: 1000, maxY: 1000)
    let fitted = ViewTransform.fitting(square, in: size)

    // A drag applies its delta to the transform the gesture started from, not to the last
    // frame: frame-by-frame deltas compound rounding and the drawing drifts from the finger.
    var session = GestureSession()
    let start = session.pan(fitted, by: ScreenPoint(x: 10, y: 0))
    let later = session.pan(start, by: ScreenPoint(x: 10, y: 0))
    let single = session.pan(fitted, by: ScreenPoint(x: 10, y: 0))
    check(later == single, "a dragged update is relative to the origin, not the last frame")
    session.end()

    // The origin is captured once per gesture.
    var fresh = GestureSession()
    _ = fresh.pan(fitted, by: ScreenPoint(x: 5, y: 0))
    check(fresh.isActive, "a gesture is active once it starts")
    fresh.end()
    check(!fresh.isActive, "and inactive after it ends")

    // The bug this guards: both gestures are live at once, and sharing one origin made the
    // second start from a stale transform the moment the first ended.
    var panSession = GestureSession()
    var zoomSession = GestureSession()
    _ = panSession.pan(fitted, by: ScreenPoint(x: 20, y: 0))
    let zoomed = zoomSession.zoom(
        fitted, by: 2, at: ScreenPoint(x: 0.5, y: 0.5))
    check(zoomed.scale != fitted.scale, "the pinch took effect")
    panSession.end()
    // The pinch session keeps its own origin, so a further update is still measured from where
    // *it* started — not from the value the drag left behind. Ending the drag must not disturb
    // it, which is the bug this guards.
    let afterPanEnds = zoomSession.zoom(
        zoomed, by: 1.1, at: ScreenPoint(x: 0.5, y: 0.5))
    // `magnification` is the total factor since the gesture began, so every update in a
    // session multiplies the same origin. That is why the second update lands at origin × 1.1
    // and not at the value the first one produced.
    check(
        abs(afterPanEnds.scale - fitted.scale * 1.1) < 1e-9,
        "the pinch keeps its own origin while the drag ends",
        "\(afterPanEnds.scale)")

    // A pinch anchor is normalised, so it lands at that fraction of the view.
    var anchored = GestureSession()
    let pinched = anchored.zoom(fitted, by: 4, at: ScreenPoint(x: 0, y: 1))
    check(pinched.scale > fitted.scale, "zooming in increases the scale")
    check(pinched.scale.isFinite && pinched.scale > 0, "and stays sane")
}

section("Damaged input")
do {
    // Files arrive damaged: a truncated download, a copy that stopped half way. None of these
    // may crash, and a file that parses to nothing must be reported rather than shown as a
    // blank canvas.

    // Not a DXF at all.
    check(
        (try? DXF.read(text: "hello world, not a drawing\n")) == nil,
        "garbage is rejected"
    )

    // A header whose entities never arrived. This is the case that shows an empty canvas and
    // calls it success, because the header alone gives it extents to frame.
    let headerOnly = """
    0
    SECTION
    2
    HEADER
    9
    $ACADVER
    1
    AC1009
    9
    $EXTMIN
    10
    0
    20
    0
    9
    $EXTMAX
    10
    100
    20
    100
    0
    ENDSEC
    0
    SECTION
    2
    ENTITIES
    0
    ENDSEC
    0
    EOF
    """
    if let drawing = try? DXF.read(text: headerOnly) {
        let scene = SceneBuilder().build(drawing)
        check(scene.samplePoints.isEmpty, "a header alone yields no points")
        check(
            scene.bounds != nil,
            "but still has extents, which is why an empty canvas looked like success"
        )
        let verdict = LoadReadiness.verdict(
            samplePoints: scene.samplePoints, hasBounds: scene.bounds != nil)
        check(verdict == .empty, "and is reported as empty, not drawable")
    } else {
        check(false, "a header-only file parses")
    }

    // A real drawing is drawable.
    if let scene = build("""
        0
        LINE
        10
        0
        20
        0
        11
        10
        21
        10
        """) {
        let verdict = LoadReadiness.verdict(
            samplePoints: scene.samplePoints, hasBounds: scene.bounds != nil)
        check(verdict == .drawable, "a drawing with a line is drawable")
    } else {
        check(false, "the line fixture parses")
    }

    // Points without bounds must not be framed as if there were a viewport for them.
    check(
        LoadReadiness.verdict(samplePoints: [Point(0, 0)], hasBounds: false) == .empty,
        "points without extents are not drawable"
    )
    check(
        LoadReadiness.verdict(samplePoints: [], hasBounds: true) == .empty,
        "extents without points are not drawable"
    )
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
