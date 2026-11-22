import Foundation
import SwiftDXF

/// Chooses the rectangle a viewer should show first.
///
/// By default this is the plain extents of the geometry, which is what a CAD drawing frame is
/// drawn to. Pass a non-zero `trim` for the drawings that do contain a runaway construction
/// line, where the extents would squeeze the content into a few pixels.
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

    /// Fits a viewport to a scene.
    ///
    /// - Parameters:
    ///   - points: every point of every primitive.
    ///   - trim: the share of coordinates cut from each side. `0` frames the extents, which is
    ///     the right default because a drawing frame is real geometry. `0.01` drops the outer
    ///     1 % and frames the content instead, for drawings with a stray long line.
    ///   - fallback: extents to use when there are too few points to judge.
    public static func fit(
        points: [Point],
        trim: Double = 0,
        fallback: Bounds?
    ) -> Viewport? {
        var accumulator = Bounds.Accumulator()
        accumulator.add(points)

        guard let everything = accumulator.bounds else {
            guard let fallback else { return nil }
            return Viewport(bounds: fallback, fullBounds: fallback, expansionFactor: 1)
        }

        // No trimming asked for, or too few points for a percentile to mean anything.
        guard trim > 0, points.count >= 20 else {
            return Viewport(
                bounds: everything, fullBounds: everything, expansionFactor: 1)
        }

        let xs = points.map(\.x).sorted()
        let ys = points.map(\.y).sorted()
        let core = Bounds(
            minX: quantile(xs, trim),
            minY: quantile(ys, trim),
            maxX: quantile(xs, 1 - trim),
            maxY: quantile(ys, 1 - trim)
        )

        // Only clip when the outliers genuinely dwarf the drawing; cropping a legitimate
        // edge is worse than a slightly loose fit.
        let fullSpan = max(everything.width, everything.height)
        let coreSpan = max(core.width, core.height)
        guard coreSpan > 0, fullSpan > coreSpan * 1.6 else {
            return Viewport(
                bounds: everything, fullBounds: everything, expansionFactor: 1)
        }

        // Keep the drawing's own aspect ratio so the framing does not distort it, and pad so
        // entities that straddle the cut are still visible.
        let aspect = everything.width / max(everything.height, .ulpOfOne)
        let side = coreSpan * 1.1
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

    private static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * q).rounded())
        return sorted[max(0, min(sorted.count - 1, index))]
    }
}
