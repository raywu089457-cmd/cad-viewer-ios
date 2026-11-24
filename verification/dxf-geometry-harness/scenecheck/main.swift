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
let verbose = args.contains("--verbose")

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// WASI Foundation cannot read a file by URL, so the bytes come in on stdin.
let data = FileHandle.standardInput.readDataToEndOfFile()
guard !data.isEmpty else {
    log("no input")
    exit(2)
}
let text = String(decoding: data, as: Unicode.ASCII.self)

// Paper space is skipped: the web viewers show model space, and comparing like with like is
// the whole point of this tool.
var options = DXF.ReadOptions()
options.expandBlocks = true
options.skipPaperSpace = true

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
            "points": line.points.map(pointObject)
        ]
    }
    let fills: [[String: Any]] = scene.fills.map { fill in
        [
            "layer": fill.layer,
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

guard wantSVG, let bounds = viewport?.bounds else { exit(0) }

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
    body.append(
        "<path d=\"\(d)\" fill=\"\(rgb(fill.color))\" fill-opacity=\"0.85\" "
            + "fill-rule=\"evenodd\" stroke=\"\(rgb(fill.color))\" "
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
    body.append(
        "<text x=\"\(text.position.x)\" y=\"\(text.position.y)\" "
            + "font-size=\"\(text.height)\" fill=\"\(rgb(text.color))\" "
            + "text-anchor=\"\(anchor)\" dominant-baseline=\"\(baseline)\" "
            + "transform=\"rotate(\(text.rotationDegrees) \(text.position.x) \(text.position.y))\" "
            + "font-family=\"Helvetica, Arial, sans-serif\">\(escapes(text.string))</text>")
}

print(
    """
    <svg xmlns="http://www.w3.org/2000/svg" \
    viewBox="\(bounds.minX - pad) \(-(bounds.maxY + pad)) \(viewWidth) \(viewHeight)" \
    width="\(Int(pixelWidth))" height="\(Int(pixelHeight))">
    <rect x="\(bounds.minX - pad)" y="\(-(bounds.maxY + pad))" \
    width="\(viewWidth)" height="\(viewHeight)" fill="#12161c"/>
    <g transform="scale(1,-1)">
    \(body.joined(separator: "\n"))
    </g></svg>
    """)
