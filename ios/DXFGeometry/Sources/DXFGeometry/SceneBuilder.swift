import Foundation
import SwiftDXF

/// A drawing flattened into primitives a renderer can draw directly.
///
/// SwiftDXF hands back a semantic model (a `SPLINE` is control points, a `HATCH` is
/// boundary paths, a `POLYLINE` may carry bulges). A canvas renderer needs curves, so
/// this flattens everything into polylines plus text, in drawing coordinates.
public struct DrawScene: Sendable {
    /// Straight-segment runs, already tessellated. Arcs, circles, ellipses, splines and
    /// polyline bulges have been converted into short segments.
    public var polylines: [Polyline] = []
    /// Text items in drawing space; the renderer applies height and rotation.
    public var texts: [TextItem] = []
    /// Filled regions (solid hatches, solids).
    public var fills: [Fill] = []
    /// Extents of everything above, in drawing units.
    public var bounds: Bounds?

    /// Entities left out because their layer is switched off or frozen, counted per layer.
    ///
    /// Empty when the file says no layer is off, or when the builder was asked not to honour
    /// the flags. Kept so a caller can tell the reader that something is not on screen — a
    /// drawing that is silently missing layers looks like a drawing that is complete.
    public var hiddenByLayer: [String: Int] = [:]

    /// Every point of every primitive, for viewport fitting.
    ///
    /// Kept separately from `bounds` because a viewer wants the dense core of the geometry,
    /// not just the outermost extents.
    public var samplePoints: [Point] = []

    public init() {}
}

/// One run of connected points.
public struct Polyline: Sendable {
    public var points: [Point]
    public var isClosed: Bool
    /// Extents of the points, computed once when the scene is built.
    ///
    /// The renderer asks whether each primitive is on screen on every frame; walking a
    /// polyline's points to answer that, for every polyline, is wasted work on a drawing
    /// with thousands of them.
    public var bounds: Bounds
    /// The ACI index as written in the file; `ACI.byLayer` when inherited.
    public var colorIndex: Int
    /// Resolved colour, already accounting for layer and background.
    public var color: RGB
    public var layer: String
}

/// A filled region; `outer` may contain holes in `holes`.
public struct Fill: Sendable {
    public var outer: [Point]
    public var holes: [[Point]]
    /// Extents of the outer loop, computed once when the scene is built.
    public var bounds: Bounds
    /// Whether to fill the region or only outline it.
    ///
    /// A HATCH is either a solid fill or a pattern — ANSI31 hatching on a section view is
    /// the common case — and the reader models the pattern's boundary but not its lines. A
    /// patterned hatch drawn as a solid block of colour is plainly wrong, so it is outlined
    /// instead: the region still reads as hatched rather than as a filled area.
    public var isSolid: Bool
    public var color: RGB
    public var layer: String
}

/// A text entity positioned in drawing space.
public struct TextItem: Sendable {
    public var string: String
    /// The anchor point; the renderer aligns the string using `attachment`.
    public var position: Point
    /// Cap height in drawing units.
    public var height: Double
    public var rotationDegrees: Double
    public var color: RGB
    public var layer: String
    public var attachment: Attachment

    public enum Attachment: Sendable {
        /// `TEXT`: the insertion point is on the baseline, at the left of the string.
        case baselineLeft
        /// A dimension label: centred on the point.
        case middleCenter
    }
}

/// Turns a parsed DXF drawing into a `DrawScene`.
public struct SceneBuilder {
    /// Chord tolerance as a fraction of the drawing's diagonal: smaller means smoother
    /// curves and more segments.
    public var curveTolerance: Double
    /// Hard cap on segments per full circle, so a tiny arc cannot explode.
    public var maxSegmentsPerCircle: Int
    /// Whether entities on a layer the file marks as switched off or frozen are drawn.
    ///
    /// DXF says a layer is off with a negative colour in group 62 and frozen with bit 1 of group
    /// 70, and every CAD application treats both as "not there". Leaving them in draws geometry
    /// the author hid on purpose.
    public var hidesSwitchedOffLayers: Bool

    public init(
        curveTolerance: Double = 0.0015,
        maxSegmentsPerCircle: Int = 180,
        hidesSwitchedOffLayers: Bool = true
    ) {
        self.curveTolerance = curveTolerance
        self.maxSegmentsPerCircle = maxSegmentsPerCircle
        self.hidesSwitchedOffLayers = hidesSwitchedOffLayers
    }

    /// Flattens a drawing read by SwiftDXF.
    ///
    /// - Parameters:
    ///   - drawing: The parsed drawing.
    ///   - onDarkBackground: Whether index-7 geometry should render white.
    public func build(_ drawing: DXF.Drawing, onDarkBackground: Bool = true) -> DrawScene {
        var scene = DrawScene()

        // Layer colours, so entities that inherit (ACI 256) resolve correctly.
        var layerColors: [String: Int] = [:]
        var hiddenLayers: Set<String> = []
        for layer in drawing.layers {
            layerColors[layer.name] = layer.color
            if hidesSwitchedOffLayers, layer.isOff || layer.isFrozen {
                hiddenLayers.insert(layer.name)
            }
        }

        // The chord error is relative to the drawing size, so a millimetre drawing and a
        // metre drawing get the same visual smoothness.
        //
        // The geometry is measured, not taken from the header. Headers are often missing
        // entirely (R12 files usually have no `$EXTMIN`) and are sometimes badly wrong: one
        // drawing here declares `$EXTMAX` a hundred times larger than anything it contains.
        // Either way the tolerance would be wrong for every curve in the file.
        let reference = max(Self.diagonal(of: drawing), 1)
        let tolerance = max(reference * curveTolerance, .ulpOfOne)

        /// The colour an entity is drawn in.
        ///
        /// `ByBlock` means "take the colour of the entity that inserted this block", not white.
        /// In practice the drawing arrives already expanded — `DrawingReadOptions.expandBlocks` —
        /// and that expansion resolves most of it: of 1462 geometric entities in
        /// `example_r12.dxf`, 49 still carry `ByBlock` and the rest name a layer whose colour is
        /// known. Painting `ByBlock` white was therefore right for almost everything and wrong for
        /// the 49, which is the kind of mistake that looks like a colour choice.
        ///
        /// `inherited` is the colour of the inserting entity, for a caller that knows it. Nil is
        /// the top level, where nothing inserted this and the layer colour is the sensible
        /// reading.
        ///
        /// `inherited` is the colour to use for `ByBlock`, resolved by the caller from whatever
        /// inserted this entity. Nil means nothing did, which is the top level: there `ByBlock`
        /// has no meaning and the layer colour is the sensible reading.
        func resolvedColor(for index: Int, layer: String, inherited: Int? = nil) -> RGB {
            let resolved: Int
            if index == ACI.byBlock {
                // The inserting entity's colour, or the layer's when nothing inserted this.
                resolved = inherited ?? layerColors[layer] ?? 7
            } else if index == ACI.byLayer || index < 0 {
                resolved = layerColors[layer] ?? 7
            } else {
                resolved = index
            }
            return ACI.rgb(resolved, onDarkBackground: onDarkBackground)
        }

        func add(_ points: [Point], closed: Bool, index: Int, layer: String) {
            guard points.count >= 2 else { return }
            scene.polylines.append(
                Polyline(
                    points: points,
                    isClosed: closed,
                    bounds: extents(of: points),
                    colorIndex: index,
                    color: resolvedColor(for: index, layer: layer),
                    layer: layer
                )
            )
        }

        for entity in drawing.entities {
            if let name = Self.layer(of: entity), hiddenLayers.contains(name) {
                scene.hiddenByLayer[name, default: 0] += 1
                continue
            }
            switch entity {
            case let .line(a, b, layer, color):
                add([Point(a.x, a.y), Point(b.x, b.y)], closed: false,
                    index: color, layer: layer)

            case let .circle(center, radius, layer, color):
                add(
                    arcPoints(
                        center: center, radius: radius, startRadians: 0,
                        sweepRadians: 2 * .pi, tolerance: tolerance),
                    closed: true, index: color, layer: layer)

            case let .arc(center, radius, startDeg, endDeg, layer, color):
                var sweep = ((endDeg - startDeg) * .pi / 180).truncatingRemainder(
                    dividingBy: 2 * .pi)
                if sweep <= 0 { sweep += 2 * .pi }
                add(
                    arcPoints(
                        center: center, radius: radius,
                        startRadians: startDeg * .pi / 180, sweepRadians: sweep,
                        tolerance: tolerance),
                    closed: false, index: color, layer: layer)

            case let .ellipse(center, majorAxis, ratio, startParam, endParam, layer, color):
                var sweep = endParam - startParam
                let full = abs(sweep) >= 2 * .pi - 1e-9
                if full { sweep = 2 * .pi }
                add(
                    ellipsePoints(
                        center: center, majorAxis: majorAxis, ratio: ratio,
                        startParam: startParam, sweep: sweep, tolerance: tolerance),
                    closed: full, index: color, layer: layer)

            case let .point(at, layer, color):
                // A POINT has no size; draw a short cross so it is visible at all zooms.
                let arm = max(tolerance * 4, reference * 0.0005)
                add(
                    [Point(at.x - arm, at.y), Point(at.x + arm, at.y)],
                    closed: false, index: color, layer: layer)
                add(
                    [Point(at.x, at.y - arm), Point(at.x, at.y + arm)],
                    closed: false, index: color, layer: layer)

            case let .text(at, height, rotationDeg, string, layer, color):
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, height > 0 else { break }
                scene.texts.append(
                    TextItem(
                        string: trimmed,
                        position: Point(at.x, at.y),
                        height: height,
                        rotationDegrees: rotationDeg,
                        color: resolvedColor(for: color, layer: layer),
                        layer: layer,
                        attachment: .baselineLeft
                    )
                )

            case let .polyline(vertices, closed, layer, color):
                let points = polylinePoints(
                    vertices: vertices, closed: closed, tolerance: tolerance)
                add(points, closed: closed, index: color, layer: layer)

            case let .hatch(hatch):
                scene.fills.append(
                    contentsOf: hatchFills(
                        hatch, tolerance: tolerance,
                        color: resolvedColor(for: hatch.color, layer: hatch.layer)))

            case let .solid(solid):
                let points = solid.corners.map { Point($0.x, $0.y) }
                guard points.count >= 3 else { break }
                scene.fills.append(
                    Fill(
                        outer: points, holes: [],
                        bounds: extents(of: points),
                        isSolid: true,
                        color: resolvedColor(for: solid.color, layer: solid.layer),
                        layer: solid.layer))
                add(points, closed: true, index: solid.color, layer: solid.layer)

            case let .face3D(face):
                let points = face.corners.map { Point($0.x, $0.y) }
                guard points.count >= 3 else { break }
                add(points, closed: true, index: face.color, layer: face.layer)

            case let .spline(spline):
                add(
                    splinePoints(spline, tolerance: tolerance),
                    closed: false, index: spline.color, layer: spline.layer)

            case let .leader(leader):
                add(
                    leader.vertices.map { Point($0.x, $0.y) },
                    closed: false, index: leader.color, layer: leader.layer)

            case let .dimension(dimension):
                for (points, closed) in dimensionGeometry(dimension, reference: reference) {
                    add(points, closed: closed, index: dimension.color,
                        layer: dimension.layer)
                }
                // SwiftDXF models the measurement, not the glyph geometry, so the value is
                // drawn at the text position instead of arrows and witness marks.
                if let label = Self.dimensionLabel(dimension) {
                    scene.texts.append(
                        TextItem(
                            string: label,
                            position: Point(
                                dimension.textPosition.x, dimension.textPosition.y),
                            height: 0,
                            rotationDegrees: dimension.rotation ?? 0,
                            color: resolvedColor(for: dimension.color, layer: dimension.layer),
                            layer: dimension.layer,
                            attachment: .middleCenter
                        )
                    )
                }

            case let .tolerance(tolerance):
                // A feature control frame is boxes and symbols; the renderer draws text. Drawing
                // each row as its written form keeps the annotation in view instead of dropping
                // it entirely, which is what used to happen — no geometry, no skip recorded,
                // nothing on screen and no way to know something was there.
                //
                // Rows stack along the frame's own y axis, one text height apart, so a composite
                // frame still reads as a frame rather than one run-on line.
                let step = reference * 0.02
                let rotation = Self.angleDegrees(
                    of: Point(tolerance.direction.x, tolerance.direction.y))
                for (row, frame) in tolerance.frames.enumerated() where !frame.raw.isEmpty {
                    scene.texts.append(
                        TextItem(
                            string: frame.raw,
                            position: Point(
                                tolerance.insertion.x,
                                tolerance.insertion.y - Double(row) * step),
                            height: 0,
                            rotationDegrees: rotation,
                            color: resolvedColor(for: tolerance.color, layer: tolerance.layer),
                            layer: tolerance.layer,
                            attachment: .baselineLeft
                        )
                    )
                }

            case let .wipeout(wipeout):
                guard wipeout.boundary.count >= 3 else { break }
                add(
                    wipeout.boundary.map { Point($0.x, $0.y) },
                    closed: true, index: wipeout.color, layer: wipeout.layer)
            }
        }

        // A dimension label has no height of its own; use the drawing's typical text size so
        // it is neither invisible nor gigantic.
        let heights = scene.texts.map(\.height).filter { $0 > 0 }.sorted()
        let fallbackHeight = heights.isEmpty
            ? reference / 100
            : heights[heights.count / 2]
        for i in scene.texts.indices where scene.texts[i].height <= 0 {
            scene.texts[i].height = fallbackHeight
        }

        // The scene's own extents are what the renderer frames; the header is only a last
        // resort when no primitive contributed a point.
        let headerFallback: Bounds? = {
            guard let lo = drawing.extMin, let hi = drawing.extMax else { return nil }
            let box = Bounds(minX: lo.x, minY: lo.y, maxX: hi.x, maxY: hi.y)
            return box.isEmpty ? nil : box
        }()
        scene.bounds = sceneBounds(scene, fallback: headerFallback)
        scene.samplePoints = gatherPoints(scene)
        return scene
    }

    /// The layer an entity sits on, or nil for a kind that carries none.
    ///
    /// Every case does carry one today; the optional is there so a kind added later without a
    /// layer is drawn rather than silently dropped.
    private static func layer(of entity: DXF.Entity) -> String? {
        switch entity {
        case let .line(_, _, layer, _): return layer
        case let .circle(_, _, layer, _): return layer
        case let .arc(_, _, _, _, layer, _): return layer
        case let .ellipse(_, _, _, _, _, layer, _): return layer
        case let .point(_, layer, _): return layer
        case let .text(_, _, _, _, layer, _): return layer
        case let .polyline(_, _, layer, _): return layer
        case let .dimension(dimension): return dimension.layer
        case let .spline(spline): return spline.layer
        case let .hatch(hatch): return hatch.layer
        case let .leader(leader): return leader.layer
        case let .tolerance(tolerance): return tolerance.layer
        case let .solid(solid): return solid.layer
        case let .wipeout(wipeout): return wipeout.layer
        case let .face3D(face): return face.layer
        }
    }

    /// The diagonal of the geometry actually present, falling back to the header extents.
    ///
    /// Measured because a header can be absent or wrong, and the curve tolerance is a
    /// fraction of this number.
    private static func diagonal(of drawing: DXF.Drawing) -> Double {
        if let measured = drawing.bounds {
            let width = measured.max.x - measured.min.x
            let height = measured.max.y - measured.min.y
            let diagonal = hypot(width, height)
            if diagonal.isFinite, diagonal > 0 { return diagonal }
        }
        guard let lo = drawing.extMin, let hi = drawing.extMax else { return 0 }
        let diagonal = hypot(hi.x - lo.x, hi.y - lo.y)
        return diagonal.isFinite ? diagonal : 0
    }

    // MARK: - Dimensions

    /// The rotation a feature control frame's box of rows runs at, in degrees.
    ///
    /// `direction` is the frame's x axis, which a block expansion may have scaled, so only its
    /// angle matters. A degenerate direction falls back to horizontal rather than to a NaN angle
    /// that would put the text nowhere.
    private static func angleDegrees(of direction: Point) -> Double {
        guard direction.x.isFinite, direction.y.isFinite else { return 0 }
        guard direction.x != 0 || direction.y != 0 else { return 0 }
        return atan2(direction.y, direction.x) * 180 / .pi
    }

    /// Draws a `DIMENSION` from its definition points.
    ///
    /// Reconstructs the extension lines and the dimension line, so a dimension reads as a
    /// dimension rather than as nothing.
    private func dimensionGeometry(
        _ d: DXF.Dimension, reference: Double
    ) -> [([Point], Bool)] {
        func point(_ p: DXF.Point) -> Point { Point(p.x, p.y) }
        var out: [([Point], Bool)] = []

        switch d.kind {
        case .linear, .aligned:
            guard let p2 = d.defPoint2, let p3 = d.defPoint3 else { break }
            // The dimension line passes through `defPoint`, offset from the measured points;
            // project them onto it so the extension lines meet it squarely.
            let a = point(p2), b = point(p3), line = point(d.defPoint)
            let dir = direction(from: a, to: b) ?? Point(1, 0)
            let normal = Point(-dir.y, dir.x)
            let offset = (line.x - a.x) * normal.x + (line.y - a.y) * normal.y
            let aOn = Point(a.x + normal.x * offset, a.y + normal.y * offset)
            let bOn = Point(b.x + normal.x * offset, b.y + normal.y * offset)
            out.append(([a, aOn], false))
            out.append(([b, bOn], false))
            // The dimension line is broken where the text sits, as CAD does, or the line
            // runs straight through the number and both become hard to read. The gap is a
            // guess at the text width: no glyph metrics are available here, and a dimension
            // label is at most a few characters.
            let label = Self.dimensionLabel(d) ?? ""
            let gapHalf = max(Double(label.count) * max(reference / 200, 1e-9) * 0.35, 0)
            if gapHalf > 0, aOn.distance(to: bOn) > gapHalf * 3 {
                let textOn = point(d.textPosition).projection(onto: aOn, bOn)
                let gapStart = min(max(textOn - gapHalf, 0), aOn.distance(to: bOn))
                let gapEnd = min(max(textOn + gapHalf, 0), aOn.distance(to: bOn))
                if gapStart > 0 { out.append(([aOn, Point.along(aOn, bOn, gapStart)], false)) }
                if gapEnd < aOn.distance(to: bOn) {
                    out.append(([Point.along(aOn, bOn, gapEnd), bOn], false))
                }
            } else {
                out.append(([aOn, bOn], false))
            }

        case .angular, .angular3Point:
            guard let p2 = d.defPoint2, let p3 = d.defPoint3 else { break }
            out.append(([point(p2), point(d.defPoint)], false))
            out.append(([point(p3), point(d.defPoint)], false))
            if let p4 = d.defPoint4 {
                out.append(([point(p4), point(d.defPoint)], false))
            }

        case .radius, .diameter:
            guard let p4 = d.defPoint4 else { break }
            out.append(([point(d.defPoint), point(p4)], false))

        case .ordinate:
            guard let p2 = d.defPoint2, let p3 = d.defPoint3 else { break }
            out.append(([point(d.defPoint), point(p2), point(p3)], false))

        case .unknown:
            break
        }
        return out
    }

    /// The text a dimension shows: its override, or the measurement.
    /// The text a dimension shows: its override with the measured value substituted in.
    ///
    /// Public because the rule is worth testing without building a scene, and because the
    /// same substitution is needed anywhere else dimensions are reported.
    public static func dimensionLabel(_ d: DXF.Dimension) -> String? {
        let value = Self.measuredText(d)

        guard let override = d.textOverride else { return value }
        // A literal space is the DXF convention for "suppress the text".
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        // `<>` is where the measured value goes; almost every dimension uses it as the
        // format, e.g. "<> mm" or "<>\\P(max)". A reader that does not substitute it shows
        // the placeholder itself, which is what happened here: nine dimensions read "<>".
        // `\\P` is a line break in MTEXT.
        return trimmed
            .replacingOccurrences(of: "<>", with: value ?? "")
            .replacingOccurrences(of: "\\P", with: "\n")
    }

    /// The measurement as text, or nil when the geometry does not give one.
    private static func measuredText(_ d: DXF.Dimension) -> String? {
        guard let value = d.computedMeasurement, value.isFinite else { return nil }
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
    }

    private func direction(from a: Point, to b: Point) -> Point? {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return nil }
        return Point(dx / length, dy / length)
    }

    // MARK: - Polyline and hatch paths

    /// Expands a polyline, including the arcs its bulges describe.
    private func polylinePoints(
        vertices: [DXF.PolyVertex], closed: Bool, tolerance: Double
    ) -> [Point] {
        guard let first = vertices.first else { return [] }
        var points = [Point(first.point.x, first.point.y)]
        let limit = closed ? vertices.count : vertices.count - 1
        for i in 0..<limit {
            let from = vertices[i]
            let to = vertices[(i + 1) % vertices.count]
            if abs(from.bulge) > 1e-12 {
                points.append(
                    contentsOf: bulgePoints(
                        from: from.point, to: to.point, bulge: from.bulge,
                        tolerance: tolerance
                    ).dropFirst()
                )
            } else {
                points.append(Point(to.point.x, to.point.y))
            }
        }
        return points
    }

    /// Hatch boundary paths as one `Fill` per external loop, with inner loops as holes.
    private func hatchFills(
        _ hatch: DXF.Hatch, tolerance: Double, color: RGB
    ) -> [Fill] {
        var outers: [[Point]] = []
        var inners: [[Point]] = []

        func outline(of geometry: DXF.Hatch.Geometry) -> [Point] {
            switch geometry {
            case let .polyline(vertices, closed):
                return polylinePoints(
                    vertices: vertices, closed: closed, tolerance: tolerance)

            case let .edges(edges):
                var points: [Point] = []
                for edge in edges {
                    switch edge {
                    case let .line(start, end):
                        if points.isEmpty { points.append(Point(start.x, start.y)) }
                        points.append(Point(end.x, end.y))

                    case let .arc(center, radius, startDeg, endDeg, counterClockwise):
                        var sweep = (endDeg - startDeg) * .pi / 180
                        if !counterClockwise { sweep = -abs(sweep) }
                        let arc = arcPoints(
                            center: DXF.Point(center.x, center.y), radius: radius,
                            startRadians: startDeg * .pi / 180, sweepRadians: sweep,
                            tolerance: tolerance)
                        if points.isEmpty { points.append(contentsOf: arc) }
                        else { points.append(contentsOf: arc.dropFirst()) }

                    case let .ellipse(
                        center, majorAxis, ratio, startParam, endParam, counterClockwise):
                        var sweep = endParam - startParam
                        if !counterClockwise { sweep = -abs(sweep) }
                        let arc = ellipsePoints(
                            center: DXF.Point(center.x, center.y),
                            majorAxis: DXF.Point(majorAxis.x, majorAxis.y),
                            ratio: ratio, startParam: startParam, sweep: sweep,
                            tolerance: tolerance)
                        if points.isEmpty { points.append(contentsOf: arc) }
                        else { points.append(contentsOf: arc.dropFirst()) }

                    case let .spline(spline):
                        let sampled = splinePoints(spline, tolerance: tolerance)
                        if points.isEmpty { points.append(contentsOf: sampled) }
                        else { points.append(contentsOf: sampled.dropFirst()) }
                    }
                }
                return points
            }
        }

        for path in hatch.paths {
            let points = outline(of: path.geometry)
            guard points.count >= 3 else { continue }
            if path.isExternal || path.isOutermost {
                outers.append(points)
            } else {
                inners.append(points)
            }
        }
        // A hatch whose only loops are islands still needs something to fill.
        if outers.isEmpty, !inners.isEmpty {
            outers.append(inners.removeFirst())
        }
        guard let primary = outers.first else { return [] }

        // Multiple outer loops are rare; treat extra ones as additional holes so nothing is
        // silently dropped.
        return [
            Fill(
                outer: primary,
                holes: inners + Array(outers.dropFirst()),
                bounds: extents(of: primary),
                isSolid: hatch.isSolid,
                color: color,
                layer: hatch.layer
            )
        ]
    }

    // MARK: - Tessellation

    /// Segment count for an arc, from the chord-height tolerance.
    private func segmentCount(radius: Double, sweep: Double, tolerance: Double) -> Int {
        guard radius > 0, sweep > 0 else { return 1 }
        // A segment spanning angle θ has sagitta r(1 - cos(θ/2)); solve for θ.
        let ratio = min(max(1 - tolerance / radius, -1), 1)
        let maxAngle = ratio <= -1 ? .pi : 2 * acos(ratio)
        let count = Int((sweep / max(maxAngle, 1e-6)).rounded(.up))
        let cap = Int(
            (Double(maxSegmentsPerCircle) * max(sweep / (2 * .pi), 1)).rounded(.up))
        return min(max(count, 2), max(cap, 2))
    }

    private func arcPoints(
        center: DXF.Point, radius: Double, startRadians: Double, sweepRadians: Double,
        tolerance: Double
    ) -> [Point] {
        guard radius > 0 else { return [] }
        let count = segmentCount(
            radius: radius, sweep: abs(sweepRadians), tolerance: tolerance)
        return (0...count).map { i in
            let angle = startRadians + sweepRadians * Double(i) / Double(count)
            return Point(
                center.x + radius * cos(angle),
                center.y + radius * sin(angle))
        }
    }

    /// An elliptical arc. `majorAxis` is the major-axis vector relative to the centre.
    private func ellipsePoints(
        center: DXF.Point, majorAxis: DXF.Point, ratio: Double, startParam: Double,
        sweep: Double, tolerance: Double
    ) -> [Point] {
        let majorLength = hypot(majorAxis.x, majorAxis.y)
        guard majorLength > 0 else { return [] }
        let minorLength = majorLength * max(abs(ratio), 1e-9)
        // The major axis is rarely world-aligned, so rotate the parametric point back.
        let rotation = atan2(majorAxis.y, majorAxis.x)
        let cosR = cos(rotation), sinR = sin(rotation)
        let count = segmentCount(
            radius: majorLength, sweep: abs(sweep), tolerance: tolerance)
        return (0...count).map { i in
            let t = startParam + sweep * Double(i) / Double(count)
            let localX = majorLength * cos(t)
            let localY = minorLength * sin(t)
            return Point(
                center.x + localX * cosR - localY * sinR,
                center.y + localX * sinR + localY * cosR)
        }
    }

    /// The arc a polyline bulge describes, as points from `from` (exclusive) to `to`.
    ///
    /// `bulge` is `tan(θ/4)` of the included angle; its sign says which way the arc turns.
    private func bulgePoints(
        from: DXF.Point, to: DXF.Point, bulge: Double, tolerance: Double
    ) -> [Point] {
        let chord = hypot(to.x - from.x, to.y - from.y)
        guard chord > 0, abs(bulge) > 1e-12 else {
            return [Point(to.x, to.y)]
        }
        let theta = 4 * atan(bulge)
        let radius = chord / (2 * sin(abs(theta) / 2))
        // The centre lies on the perpendicular bisector, offset by the apothem.
        let midX = (from.x + to.x) / 2, midY = (from.y + to.y) / 2
        let nx = -(to.y - from.y) / chord, ny = (to.x - from.x) / chord
        let apothem = radius * cos(theta / 2)
        let direction: Double = theta > 0 ? 1 : -1
        let centerX = midX + nx * apothem * direction
        let centerY = midY + ny * apothem * direction

        let startAngle = atan2(from.y - centerY, from.x - centerX)
        let count = segmentCount(
            radius: radius, sweep: abs(theta), tolerance: tolerance)
        return (1...count).map { i in
            let angle = startAngle + theta * Double(i) / Double(count)
            return Point(centerX + radius * cos(angle), centerY + radius * sin(angle))
        }
    }

    /// Samples a NURBS spline with de Boor's algorithm.
    ///
    /// Falls back to the fit points when the control data is unusable, which is what a
    /// viewer should show rather than nothing.
    private func splinePoints(_ spline: DXF.Spline, tolerance: Double) -> [Point] {
        func point(_ p: DXF.Point) -> Point { Point(p.x, p.y) }
        let control = spline.controlPoints
        let degree = max(1, min(spline.degree, 10))
        let knots = spline.knots
        guard control.count > degree, knots.count >= control.count + degree + 1 else {
            return spline.fitPoints.map(point)
        }

        let start = knots[degree]
        let end = knots[control.count]
        guard end > start else { return control.map(point) }

        let spanCount = max(control.count - degree, 1)
        let samples = max(32, spanCount * 16)
        let weights: [Double]? = spline.weights.count == control.count
            ? spline.weights
            : nil

        return (0...samples).map { i in
            let t = start + (end - start) * Double(i) / Double(samples)
            return deBoor(
                t: t, degree: degree, control: control, knots: knots, weights: weights)
        }
    }

    /// One point on a (rational) B-spline, via de Boor.
    private func deBoor(
        t: Double, degree: Int, control: [DXF.Point], knots: [Double], weights: [Double]?
    ) -> Point {
        let n = control.count - 1
        // The knot span containing t.
        var span = degree
        if t >= knots[n + 1] {
            span = n
        } else {
            for k in degree...n where knots[k] <= t && t < knots[k + 1] {
                span = k
                break
            }
        }

        // Seed with degree+1 control points in homogeneous coordinates.
        var px = [Double](repeating: 0, count: degree + 1)
        var py = [Double](repeating: 0, count: degree + 1)
        var pw = [Double](repeating: 0, count: degree + 1)
        for j in 0...degree {
            let index = min(max(span - degree + j, 0), n)
            let w = weights?[index] ?? 1
            px[j] = control[index].x * w
            py[j] = control[index].y * w
            pw[j] = w
        }

        for r in 1...degree {
            for j in stride(from: degree, through: r, by: -1) {
                let i = j + span - degree
                let denominator = knots[i + degree - r + 1] - knots[i]
                let alpha = denominator == 0 ? 0 : (t - knots[i]) / denominator
                let oneMinus = 1 - alpha
                px[j] = oneMinus * px[j - 1] + alpha * px[j]
                py[j] = oneMinus * py[j - 1] + alpha * py[j]
                pw[j] = oneMinus * pw[j - 1] + alpha * pw[j]
            }
        }

        let w = pw[degree]
        guard w != 0 else { return Point(px[degree], py[degree]) }
        return Point(px[degree] / w, py[degree] / w)
    }

    /// Extents of a point list, for the renderer's per-frame culling.
    private func extents(of points: [Point]) -> Bounds {
        var accumulator = Bounds.Accumulator()
        accumulator.add(points)
        return accumulator.bounds ?? Bounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
    }

    // MARK: - Bounds

    /// Every point a viewport fit should consider.
    private func gatherPoints(_ scene: DrawScene) -> [Point] {
        var points: [Point] = []
        points.reserveCapacity(scene.polylines.reduce(0) { $0 + $1.points.count })
        for line in scene.polylines { points.append(contentsOf: line.points) }
        for fill in scene.fills {
            points.append(contentsOf: fill.outer)
            for hole in fill.holes { points.append(contentsOf: hole) }
        }
        for text in scene.texts {
            points.append(text.position)
            points.append(
                Point(
                    text.position.x + Double(text.string.count) * text.height * 0.6,
                    text.position.y + text.height))
        }
        return points
    }

    /// Extents over every primitive, falling back to the header extents.
    private func sceneBounds(_ scene: DrawScene, fallback: Bounds?) -> Bounds? {
        var accumulator = Bounds.Accumulator()
        var sawGeometry = false

        for line in scene.polylines {
            accumulator.add(line.points)
            sawGeometry = true
        }
        for fill in scene.fills {
            accumulator.add(fill.outer)
            for hole in fill.holes { accumulator.add(hole) }
            sawGeometry = true
        }
        for text in scene.texts {
            accumulator.add(text.position)
            // A text item's box runs right and up from its anchor.
            accumulator.add(
                Point(
                    text.position.x + Double(text.string.count) * text.height * 0.6,
                    text.position.y + text.height))
            sawGeometry = true
        }

        guard sawGeometry else { return fallback }
        return accumulator.bounds ?? fallback
    }
}
