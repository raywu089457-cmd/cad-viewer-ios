import Foundation
import SwiftDXF

/// Chooses the rectangle a viewer should show first.
///
/// Two things make this necessary. First, DXF headers routinely declare extents far larger
/// than the geometry: one real drawing here declares `$EXTMAX` at 860 276 while 99 % of its
/// entities sit within 35 000, so framing on the header shows the drawing as a dot. Second,
/// a stray construction line or an exploded block can lie kilometres from everything else.
///
/// So the initial view frames the dense core of the geometry, and remembers the full extents
/// so the UI can say that something lies outside it.
public struct Viewport: Equatable, Sendable {
    /// The rectangle to show, in drawing units.
    public var bounds: Bounds
    /// Extents of every primitive, including the ones left out of `bounds`.
    public var fullBounds: Bounds
    /// How many times larger the full extents are than the shown area; `1` means nothing was
    /// clipped away.
    public var expansionFactor: Double

    /// `true` when geometry lies outside the initial view.
    public var hasGeometryOutside: Bool { expansionFactor > 1.0001 }

    /// The share of points cut from each side when the outlier is severe enough to matter.
    ///
    /// Small enough that a normal drawing's edges survive: 0.5 % of the coordinates, so a
    /// rectangle drawn to the very edge of the content is still on screen.
    static let trimFraction: Double = 0.005

    /// How much larger the full extents must be before trimming is worth doing.
    ///
    /// Below this the drawing is simply shown in full, because cropping a legitimate edge is
    /// worse than a slightly loose fit.
    static let trimThreshold: Double = 1.6

    /// Fits a viewport to a scene.
    ///
    /// - Parameters:
    ///   - points: every point of every primitive.
    ///   - fallback: extents to use when there are too few points to judge.
    public static func fit(
        points: [Point],
        fallback: Bounds?
    ) -> Viewport? {
        var accumulator = Bounds.Accumulator()
        accumulator.add(points)

        guard let everything = accumulator.bounds else {
            guard let fallback else { return nil }
            return Viewport(bounds: fallback, fullBounds: fallback, expansionFactor: 1)
        }

        // A drawing of one point, or of a single straight line, has zero extent on one axis
        // — and for a lone point on both. Framing that literally gives a zero-size viewport,
        // and the viewer then divides by it: the drawing appears as nothing at all. A small
        // box around the point is what the reader needs to see anything.
        let usable = Self.paddedIfDegenerate(everything)

        // Too few points for a percentile to mean anything: show everything.
        guard points.count >= 20 else {
            return Viewport(
                bounds: usable, fullBounds: everything, expansionFactor: 1)
        }

        let xs = points.map(\.x).sorted()
        let ys = points.map(\.y).sorted()
        let core = Bounds(
            minX: quantile(xs, trimFraction),
            minY: quantile(ys, trimFraction),
            maxX: quantile(xs, 1 - trimFraction),
            maxY: quantile(ys, 1 - trimFraction)
        )

        // Only clip when the outliers genuinely dwarf the drawing.
        let fullSpan = max(everything.width, everything.height)
        let coreSpan = max(core.width, core.height)
        guard coreSpan > 0, fullSpan > coreSpan * trimThreshold else {
            return Viewport(
                bounds: everything, fullBounds: everything, expansionFactor: 1)
        }

        // Keep the drawing's own aspect ratio so the framing does not distort it, and take
        // the union of the core with the centre, so a lopsided drawing is not pushed off
        // screen.
        let aspect = everything.width / max(everything.height, .ulpOfOne)
        let side = coreSpan * 1.05
        let width = aspect >= 1 ? side : side * aspect
        let height = aspect >= 1 ? side / aspect : side
        let centerX = (core.minX + core.maxX) / 2
        let centerY = (core.minY + core.maxY) / 2
        let framed = Bounds(
            minX: centerX - width / 2,
            minY: centerY - height / 2,
            maxX: centerX + width / 2,
            maxY: centerY + height / 2
        )
        return Viewport(
            bounds: framed,
            fullBounds: everything,
            expansionFactor: fullSpan / max(width, height)
        )
    }

    /// A quantile of an already-sorted array.
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * q).rounded())
        return sorted[max(0, min(sorted.count - 1, index))]
    }

    /// A bounds with a non-zero extent on both axes.
    ///
    /// A single point, or a horizontal line, has zero height. Framing that literally produces
    /// a viewport the viewer cannot fit into, so a degenerate axis is given a small span around
    /// the centre — proportional to the other axis when there is one, so a very wide line still
    /// looks like a line rather than a dot.
    static func paddedIfDegenerate(_ bounds: Bounds) -> Bounds {
        let width = bounds.width
        let height = bounds.height
        guard width <= 0 || height <= 0 else { return bounds }

        let centreX = (bounds.minX + bounds.maxX) / 2
        let centreY = (bounds.minY + bounds.maxY) / 2
        // A twentieth of whichever axis has extent, or one unit when neither does.
        let span = max(max(width, height) / 20, 1)
        let halfWidth = max(width, span) / 2
        let halfHeight = max(height, span) / 2
        return Bounds(
            minX: centreX - halfWidth,
            minY: centreY - halfHeight,
            maxX: centreX + halfWidth,
            maxY: centreY + halfHeight
        )
    }
}
