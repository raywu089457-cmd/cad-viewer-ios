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
let square = Bounds(minX: 0, minY: 0, maxX: 1000, maxY: 1000)
if let plain = Viewport.fit(points: [Point(0, 0), Point(1000, 1000)], fallback: square) {
    check(plain.bounds == square, "frames the extents by default")
    check(!plain.hasGeometryOutside, "nothing outside")
} else {
    check(false, "viewport from two points")
}

// One point far away must not shrink the frame when trimming is off (the default), but
// must when trimming is asked for.
do {
    var points: [Point] = []
    for i in 0..<100 { points.append(Point(Double(i), Double(i % 10))) }
    points.append(Point(1_000_000, 1_000_000))

    if let untrimmed = Viewport.fit(points: points, fallback: nil) {
        check(untrimmed.bounds.maxX >= 1_000_000, "default keeps the outlier in frame")
    } else {
        check(false, "untrimmed viewport")
    }
    if let trimmed = Viewport.fit(points: points, trim: 0.01, fallback: nil) {
        check(trimmed.bounds.maxX < 1000, "trim drops the outlier", "\(trimmed.bounds.maxX)")
        check(trimmed.hasGeometryOutside, "and reports that something is outside")
        check(trimmed.expansionFactor > 1, "expansion factor > 1")
    } else {
        check(false, "trimmed viewport")
    }
}

// MARK: - View transform

section("View transform")
let portrait = ScreenSize(width: 390, height: 844)

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

// MARK: - Result

print("")
if failures == 0 {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAILED — \(failures) of \(checks) checks")
    exit(1)
}
