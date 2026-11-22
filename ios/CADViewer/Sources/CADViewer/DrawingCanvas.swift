import SwiftUI
import DXFGeometry

/// Draws a flattened drawing with a pan/zoom transform.
///
/// The renderer walks the primitives once per frame and skips anything off screen, so a
/// large drawing stays usable while a detail is being inspected.
struct DrawingCanvas: View {
    var scene: DrawScene
    var transform: ViewTransform
    var background: Color
    /// Line width in screen points. CAD line weights are ignored, as most viewers do.
    var lineWidth: Double = 1

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, _ in
            context.fill(
                Path(CGRect(origin: .zero, size: transform.cgSize)),
                with: .color(background)
            )
            drawShapes(in: &context)
            drawText(in: &context)
        }
    }

    /// Fills and strokes every visible primitive.
    private func drawShapes(in context: inout GraphicsContext) {
        for fill in scene.fills {
            guard fill.outer.count >= 3 else { continue }
            guard transform.isVisible(bounds(of: fill.outer)) else { continue }
            var path = polygonPath(fill.outer)
            // Even-odd so inner loops cut holes, as a hatch island should.
            for hole in fill.holes where hole.count >= 3 {
                path.addPath(polygonPath(hole))
            }
            context.fill(
                path,
                with: .color(fill.color.swiftUIColor),
                style: .init(eoFill: true)
            )
        }

        for line in scene.polylines {
            guard line.points.count >= 2 else { continue }
            guard transform.isVisible(bounds(of: line.points)) else { continue }
            var path = polylinePath(line.points)
            if line.isClosed { path.closeSubpath() }
            context.stroke(
                path,
                with: .color(line.color.swiftUIColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Text is drawn in its own pass: mixing rotated text into a filled path pass loses the
    /// per-item transform.
    private func drawText(in context: inout GraphicsContext) {
        for item in scene.texts {
            let anchor = transform.screenPoint(for: item.position)
            // Text smaller than a few points is unreadable and costs time to lay out.
            let screenHeight = item.height * transform.scale
            guard screenHeight >= 3 else { continue }
            guard CGRect(origin: .zero, size: transform.cgSize)
                .insetBy(dx: -60, dy: -60)
                .contains(anchor.cgPoint)
            else { continue }

            // Drawing space y is up, so a positive CAD rotation is counter-clockwise; screen
            // space is flipped, so the angle is negated.
            let radians = -item.rotationDegrees * .pi / 180
            let text = Text(item.string)
                .font(.system(size: screenHeight))
                .foregroundStyle(item.color.swiftUIColor)

            var resolved = context
            resolved.translateBy(x: anchor.x, y: anchor.y)
            resolved.rotate(by: .radians(radians))
            switch item.attachment {
            case .baselineLeft:
                // The CAD insertion point is the baseline start, so no extra offset.
                resolved.draw(text, at: .zero, anchor: .bottomLeading)
            case .middleCenter:
                resolved.draw(text, at: .zero, anchor: .center)
            }
        }
    }

    /// A path through the points, converted to screen space.
    private func polylinePath(_ points: [Point]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: transform.screenPoint(for: first).cgPoint)
        for point in points.dropFirst() {
            path.addLine(to: transform.screenPoint(for: point).cgPoint)
        }
        return path
    }

    private func polygonPath(_ points: [Point]) -> Path {
        var path = polylinePath(points)
        if !points.isEmpty { path.closeSubpath() }
        return path
    }

    /// Extents of a primitive, for the culling test.
    private func bounds(of points: [Point]) -> Bounds {
        var accumulator = Bounds.Accumulator()
        accumulator.add(points)
        // A culled rectangle of zero size would be visible at every zoom level.
        return accumulator.bounds ?? Bounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
    }
}

extension RGB {
    /// The SwiftUI colour for this RGB value.
    var swiftUIColor: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension ViewTransform {
    /// The view size as a `CGSize`, for view code that needs one.
    var cgSize: CGSize { CGSize(width: viewSize.width, height: viewSize.height) }
}

extension ScreenPoint {
    /// The point as a `CGPoint`, for view code that needs one.
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension CGSize {
    /// The size as a `ScreenSize`.
    var screenSize: ScreenSize {
        ScreenSize(width: width, height: height)
    }
}

extension CGPoint {
    /// The point as a `ScreenPoint`.
    var screenPoint: ScreenPoint { ScreenPoint(x: x, y: y) }

    /// The point as an anchor in `UnitPoint` terms, which is what `MagnifyGesture` reports.
    var unitPoint: UnitPoint { UnitPoint(x: x, y: y) }
}

extension ScreenSize {
    /// The size as a `CGSize`, for `Canvas` and friends.
    var cgSize: CGSize { CGSize(width: width, height: height) }
}
