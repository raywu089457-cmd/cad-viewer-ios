import Foundation
import DXFGeometry
import SwiftDXF

// scenecheck: parse a DXF from stdin, flatten it with SceneBuilder, and optionally emit an
// SVG so the native geometry can be compared against the web viewers on the same file.
//
//   scenecheck [--svg | --json] [--verbose]

let args = Array(CommandLine.arguments.dropFirst())
let wantSVG = args.contains("--svg")
let wantJSON = args.contains("--json")
/// `--verify-fresh <path>`: compare the geometry with a committed snapshot and exit 1 on a
/// difference. In here rather than in a script because the Swift CI image carries neither
/// node nor python, and this is the one tool that is already built there.
let verifyFreshIndex = args.firstIndex(of: "--verify-fresh")
let verifyFreshPath = verifyFreshIndex.flatMap { index in
    index + 1 < args.count ? args[index + 1] : nil
}
let verbose = args.contains("--verbose")

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// Normally the bytes come in on stdin, because WASI Foundation cannot read a file by URL. A native
// build can, so `--file <path>` exists for checks that cut a real drawing into pieces and need to
// run the tool once per piece: stdin can only be consumed once.
let fileIndex = args.firstIndex(of: "--file")
let filePath = fileIndex.flatMap { index in
    index + 1 < args.count ? args[index + 1] : nil
}

let data: Data
if let filePath {
    guard let read = FileManager.default.contents(atPath: filePath) else {
        log("cannot read \(filePath)")
        exit(2)
    }
    data = read
} else {
    data = FileHandle.standardInput.readDataToEndOfFile()
}
// The `--truncations` flag brings its own input; there is nothing on stdin in that case, and
// asking for both would make it unusable from a step that has the file and no pipe to feed it.
let truncIndex = args.firstIndex(of: "--truncations")
let truncPath = truncIndex.flatMap { i in i + 1 < args.count ? args[i + 1] : nil }

if truncIndex == nil {
    guard !data.isEmpty else {
        log("no input")
        exit(2)
    }
}
let text = String(decoding: data, as: Unicode.ASCII.self)

// `--truncations`: cut this drawing at each tenth of its bytes and report what every cut did.
//
// The harness does the same with a synthetic fixture, which stops in tidy places — after a
// complete entity, between sections. A file arrives damaged by being cut off wherever a download
// stopped, which lands inside a group code or halfway through a coordinate. This runs the real
// file through the same `DXF.read` and `LoadReadiness` the app uses.
if truncIndex != nil {
    let options = DrawingReadOptions.app
    // `--truncations <path>` carries its own path, because the tool may have been given one with
    // `--file` or none at all. Reading it here means the argument is self-contained.
    let whole: Data
    if let truncPath {
        guard let read = FileManager.default.contents(atPath: truncPath) else {
            log("cannot read \(truncPath)")
            exit(2)
        }
        whole = read
    } else {
        whole = data
    }
    var drew = 0
    var reported = 0
    for tenth in 1...10 {
        let cut = whole.count * tenth / 10
        let piece = String(decoding: whole.prefix(cut), as: Unicode.ASCII.self)
        guard let partial = try? DXF.read(text: piece, options: options) else {
            reported += 1
            print("      \(cut) of \(whole.count) bytes: reported")
            continue
        }
        let partScene = SceneBuilder().build(partial)
        let verdict = LoadReadiness.verdict(
            samplePoints: partScene.samplePoints, hasBounds: partScene.bounds != nil)
        if verdict == .drawable {
            drew += 1
            print("      \(cut) of \(whole.count) bytes: drew")
        } else {
            reported += 1
            print("      \(cut) of \(whole.count) bytes: reported")
        }
    }
    // Every cut lands in exactly one of the two, and a build that drew all ten would mean
    // truncation is invisible — the reader would be shown a partial drawing with nothing saying so.
    if drew + reported == 10 && reported > 0 {
        print("TRUNCATIONS OK — \(drew) drew, \(reported) reported")
        exit(0)
    }
    print("TRUNCATIONS FAILED — \(drew) drew, \(reported) reported")
    exit(1)
}

// The app's own options, so this tool shows what the app shows. Paper space is skipped, the
// web viewers show model space, and comparing like with like is the whole point of this tool.
let options = DrawingReadOptions.app

let started = Date()
let drawing: DXF.Drawing
do {
    drawing = try DXF.read(text: text, options: options)
} catch {
    log("PARSE ERROR: \(error)")
    exit(1)
}
let parseMS = Int(Date().timeIntervalSince(started) * 1000)

let buildStarted = Date()
let scene = SceneBuilder().build(drawing)
let buildMS = Int(Date().timeIntervalSince(buildStarted) * 1000)

// The initial view frames the dense core of the drawing, so one stray entity cannot shrink
// everything else to a dot.
let viewport = Viewport.fit(points: scene.samplePoints, fallback: scene.bounds)

func escapes(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

func rgb(_ color: RGB) -> String {
    String(
        format: "#%02x%02x%02x",
        Int((color.r * 255).rounded()),
        Int((color.g * 255).rounded()),
        Int((color.b * 255).rounded()))
}

let counts = drawing.counts
log("version=\(drawing.version)")
log("entities=\(counts.total) LINE=\(counts.line) CIRCLE=\(counts.circle) ARC=\(counts.arc)")
log("  ELLIPSE=\(counts.ellipse) POLYLINE=\(counts.polyline) TEXT=\(counts.text) DIM=\(counts.dimension)")
log("  HATCH=\(counts.hatch) SPLINE=\(counts.spline) SOLID=\(counts.solid) LEADER=\(counts.leader)")
log("parse_ms=\(parseMS) build_ms=\(buildMS) skipped=\(drawing.skipped.count)")
if verbose || !drawing.skipped.isEmpty {
    // Which entity types were dropped, not just how many: an unread type is silent data loss
    // and the count alone does not say whether any of it mattered.
    for (type, count) in drawing.skipped.sorted(by: { $0.key < $1.key }) {
        log("  skipped: \(type) x\(count)")
    }
}
log("scene: polylines=\(scene.polylines.count) fills=\(scene.fills.count) texts=\(scene.texts.count)")
if let b = scene.bounds {
    log(
        "bounds=[\(b.minX),\(b.minY)]-[\(b.maxX),\(b.maxY)] size=\(b.width)x\(b.height)")
}
if let v = viewport {
    log(
        "viewport=[\(v.bounds.minX),\(v.bounds.minY)]-[\(v.bounds.maxX),\(v.bounds.maxY)] "
            + "expansion=\(Int(v.expansionFactor.rounded()))x "
            + "outside=\(v.hasGeometryOutside)")
}

if verbose {
    let layers = Dictionary(grouping: scene.polylines, by: \.layer)
        .map { "\($0.key):\($0.value.count)" }
        .sorted()
    log("layers: " + layers.joined(separator: " "))
}

// The committed snapshot has to still match what the pipeline produces, or the independent
// coordinate check is comparing two stale copies of the same thing.
if let path = verifyFreshPath {
    guard let data = FileManager.default.contents(atPath: path) else {
        log("cannot read the snapshot at \(path)")
        exit(1)
    }
    guard
        let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let storedPolylines = stored["polylines"] as? [[String: Any]]
    else {
        log("the snapshot at \(path) is not in the shape this writes")
        exit(1)
    }

    if storedPolylines.count != scene.polylines.count {
        log(
            "polyline count differs: \(scene.polylines.count) produced, "
                + "\(storedPolylines.count) committed")
        exit(1)
    }

    for (index, line) in scene.polylines.enumerated() {
        guard let storedPoints = storedPolylines[index]["points"] as? [[String: Any]] else {
            log("polyline \(index) in the snapshot has no points")
            exit(1)
        }
        if storedPoints.count != line.points.count {
            log(
                "polyline \(index) has \(line.points.count) points, "
                    + "committed has \(storedPoints.count)")
            exit(1)
        }
        for (position, point) in line.points.enumerated() {
            let storedX = storedPoints[position]["x"] as? Double ?? .nan
            let storedY = storedPoints[position]["y"] as? Double ?? .nan
            if abs(point.x - storedX) > 1e-6 || abs(point.y - storedY) > 1e-6 {
                log(
                    "polyline \(index) point \(position): (\(point.x), \(point.y)) produced, "
                        + "(\(storedX), \(storedY)) committed")
                exit(1)
            }
        }
    }

    log("the fixture snapshot is current (\(scene.polylines.count) polylines)")
    exit(0)
}

// A machine-readable dump, so the flattened geometry can be checked entity by entity
// against the DXF the library read.
if wantJSON {
    func pointObject(_ p: Point) -> [String: Any] { ["x": p.x, "y": p.y] }
    let polylines: [[String: Any]] = scene.polylines.enumerated().map { index, line in
        [
            "index": index,
            "layer": line.layer,
            "closed": line.isClosed,
            "colorIndex": line.colorIndex,
            // The colour it is actually drawn in: index 256 means ByLayer, which resolves
            // differently per layer, so the index alone does not say what is on screen.
            "rgb": [line.color.r, line.color.g, line.color.b],
            "points": line.points.map(pointObject)
        ]
    }
    let fills: [[String: Any]] = scene.fills.map { fill in
        [
            "layer": fill.layer,
            "isSolid": fill.isSolid,
            "outer": fill.outer.map(pointObject),
            "holes": fill.holes.map { $0.map(pointObject) },
            "rgb": [fill.color.r, fill.color.g, fill.color.b]
        ]
    }
    let texts: [[String: Any]] = scene.texts.map { text in
        [
            "layer": text.layer,
            "string": text.string,
            "x": text.position.x,
            "y": text.position.y,
            "height": text.height
        ]
    }
    let payload: [String: Any] = [
        "version": drawing.version,
        "counts": [
            "total": counts.total, "line": counts.line, "circle": counts.circle,
            "arc": counts.arc, "ellipse": counts.ellipse, "polyline": counts.polyline,
            "text": counts.text, "dimension": counts.dimension, "hatch": counts.hatch,
            "spline": counts.spline, "solid": counts.solid, "leader": counts.leader
        ],
        "polylines": polylines,
        "fills": fills,
        "texts": texts
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload),
        let string = String(data: data, encoding: .utf8)
    {
        print(string)
    }
    exit(0)
}

// `--verify-svg` produces the same document and then checks it, so it needs one built.
guard wantSVG || args.contains("--verify-svg"), let bounds = viewport?.bounds else { exit(0) }

// A margin so strokes near the edge are not clipped, and the same y-flip the web uses.
let pad = max(bounds.width, bounds.height) * 0.05
let viewWidth = bounds.width + pad * 2
let viewHeight = bounds.height + pad * 2
let pixelWidth = 1000.0
let pixelHeight = (pixelWidth * viewHeight / viewWidth).rounded()

var body: [String] = []
body.reserveCapacity(scene.polylines.count + scene.fills.count + scene.texts.count)

for fill in scene.fills {
    func path(_ points: [Point]) -> String {
        guard let first = points.first else { return "" }
        var d = "M \(first.x) \(first.y)"
        for point in points.dropFirst() { d += " L \(point.x) \(point.y)" }
        return d + " Z"
    }
    var d = path(fill.outer)
    for hole in fill.holes { d += " " + path(hole) }
    // A patterned hatch is outlined, not filled: this tool must show what the app shows, or
    // comparing the two is meaningless.
    let paint = fill.isSolid
        ? "fill=\"\(rgb(fill.color))\" fill-opacity=\"0.85\" fill-rule=\"evenodd\" "
        : "fill=\"none\" "
    body.append(
        "<path d=\"\(d)\" \(paint)stroke=\"\(rgb(fill.color))\" "
            + "stroke-width=\"1\" vector-effect=\"non-scaling-stroke\"/>")
}

for line in scene.polylines {
    guard line.points.count >= 2 else { continue }
    var d = "M \(line.points[0].x) \(line.points[0].y)"
    for point in line.points.dropFirst() { d += " L \(point.x) \(point.y)" }
    if line.isClosed { d += " Z" }
    body.append(
        "<path d=\"\(d)\" fill=\"none\" stroke=\"\(rgb(line.color))\" "
            + "stroke-width=\"1\" vector-effect=\"non-scaling-stroke\"/>")
}

for text in scene.texts {
    let anchor = text.attachment == .middleCenter ? "middle" : "start"
    let baseline = text.attachment == .middleCenter ? "central" : "alphabetic"
    // The drawing sits in a scale(1,-1) group, which would mirror the glyphs. Text is wrapped
    // in a counter-flip so it reads the right way up, and the rotation is negated for the same
    // reason the app negates it: drawing space is y-up, screen space is y-down.
    let flip =
        "translate(\(text.position.x) \(text.position.y)) "
        + "rotate(\(-text.rotationDegrees)) scale(1,-1) "
        + "translate(\(-text.position.x) \(-text.position.y))"
    body.append(
        "<text x=\"\(text.position.x)\" y=\"\(text.position.y)\" "
            + "font-size=\"\(text.height)\" fill=\"\(rgb(text.color))\" "
            + "text-anchor=\"\(anchor)\" dominant-baseline=\"\(baseline)\" "
            + "transform=\"\(flip)\" "
            + "font-family=\"Helvetica, Arial, sans-serif\">\(escapes(text.string))</text>")
}

let document = """
    <svg xmlns="http://www.w3.org/2000/svg" \
    viewBox="\(bounds.minX - pad) \(-(bounds.maxY + pad)) \(viewWidth) \(viewHeight)" \
    width="\(Int(pixelWidth))" height="\(Int(pixelHeight))">
    <rect x="\(bounds.minX - pad)" y="\(-(bounds.maxY + pad))" \
    width="\(viewWidth)" height="\(viewHeight)" fill="#12161c"/>
    <g transform="scale(1,-1)">
    \(body.joined(separator: "\n"))
    </g></svg>
    """

// `--verify-svg <path>`: compare the rendering against a committed snapshot, and check that what
// came out is drawable at all. The assertions live here rather than in a script because the image
// this runs in carries no node, and a rendering nobody inspects is the same as no rendering.
let verifySVGIndex = args.firstIndex(of: "--verify-svg")
let verifySVGPath = verifySVGIndex.flatMap { index in
    index + 1 < args.count ? args[index + 1] : nil
}

if let verifySVGPath {
    var failed = 0
    func verdict(_ ok: Bool, _ what: String) {
        print((ok ? "ok    " : "FAIL  ") + what)
        if !ok { failed += 1 }
    }

    // Every shape the renderer emitted, with the path data between the quotes.
    var paths: [String] = []
    var scanning = document.startIndex
    while let open = document.range(of: "<path d=\"", range: scanning..<document.endIndex) {
        guard let close = document.range(of: "\"", range: open.upperBound..<document.endIndex)
        else { break }
        paths.append(String(document[open.upperBound..<close.lowerBound]))
        scanning = close.upperBound
    }

    // Closed paths come from circles, open ones from lines. Comparing against the entity counts
    // in the file is what says the renderer drew what was asked for rather than something else.
    let closed = paths.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("Z") }
    let open = paths.count - closed.count
    verdict(
        closed.count == counts.circle,
        "\(closed.count) closed path(s) for \(counts.circle) CIRCLE entit(ies)")
    verdict(
        open == counts.line,
        "\(open) open path(s) for \(counts.line) LINE entit(ies)")

    // A path whose `d` holds no digits is a shape that draws nothing, and an element count would
    // never notice it.
    let coordinateLess = paths.filter { $0.rangeOfCharacter(from: .decimalDigits) == nil }
    verdict(coordinateLess.isEmpty, "every path carries coordinates")

    // Correct geometry that is not painted is invisible to every geometry check.
    var strokes = 0
    var strokeLess = 0
    var strokeScan = document.startIndex
    while let open = document.range(of: "<path ", range: strokeScan..<document.endIndex) {
        guard let close = document.range(of: "/>", range: open.upperBound..<document.endIndex)
        else { break }
        let element = document[open.upperBound..<close.lowerBound]
        if element.contains("stroke=\"#") { strokes += 1 }
        else if element.contains("stroke=\"none\"") || !element.contains("stroke=") {
            strokeLess += 1
        }
        strokeScan = close.upperBound
    }
    verdict(strokes == paths.count, "every path has a stroke (\(strokes) of \(paths.count))")
    verdict(strokeLess == 0, "and none is stroke-less, which would draw nothing")

    // The snapshot, so a change to the rendering is visible rather than absorbed.
    //
    // WASI Foundation cannot open a path, so the comparison only runs where the tool is built
    // natively — which is CI. Skipping it there is said out loud: a check that quietly does less
    // depending on where it runs is a check whose green means different things.
    if let committed = FileManager.default.contents(atPath: verifySVGPath),
        let expected = String(data: committed, encoding: .utf8)
    {
        let normalise: (String) -> [String] = { text in
            text.split(separator: "\n").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }
        verdict(normalise(expected) == normalise(document), "\(verifySVGPath) matches the rendering")
    } else {
        print("SKIP  \(verifySVGPath) is not readable here, so it was not compared")
    }

    if failed > 0 {
        print("\n\(failed) rendering problem(s)")
        exit(1)
    }
    print("\nthe renderer produced \(paths.count) drawable path(s)")
    exit(0)
}

print(document)
