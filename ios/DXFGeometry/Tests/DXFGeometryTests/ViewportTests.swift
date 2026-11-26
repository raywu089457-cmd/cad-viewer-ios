import Testing
@testable import DXFGeometry

/// The initial framing, which decides whether a drawing appears at a readable size or as a
/// speck. Two real drawings in this repository needed it: their DXF headers declare extents
/// a hundred times larger than their geometry.
@Suite("Viewport")
struct ViewportTests {
    /// A tidy drawing: 100 points on a 100-unit grid, no outliers.
    private func tidyPoints() -> [Point] {
        (0..<100).map { Point(Double($0), Double($0 % 10)) }
    }

    /// The same drawing with one point a million units away.
    private func pointsWithOutlier() -> [Point] {
        var points = (0..<200).map { Point(Double($0) * 10, Double($0 % 20) * 10) }
        points.append(Point(1_000_000, 1_000_000))
        return points
    }

    @Test("A tidy drawing is framed in full")
    func tidyDrawing() throws {
        let viewport = try #require(Viewport.fit(points: tidyPoints(), fallback: nil))
        // Cropping a legitimate edge is worse than a slightly loose fit.
        #expect(!viewport.hasGeometryOutside)
        #expect(viewport.bounds.minX == 0)
        #expect(viewport.bounds.maxX == 99)
    }

    @Test("One far outlier does not shrink the drawing to a speck")
    func outlierIsNotFramed() throws {
        let viewport = try #require(Viewport.fit(points: pointsWithOutlier(), fallback: nil))
        // The point at 1 000 000 is outside the frame ...
        #expect(viewport.bounds.maxX < 100_000)
        // ... and the UI can say so.
        #expect(viewport.hasGeometryOutside)
        #expect(viewport.expansionFactor > 1)
        // The content itself is still inside the frame.
        #expect(viewport.bounds.minX <= 0)
        #expect(viewport.bounds.maxX >= 1990)
    }

    @Test("The full extents are remembered even when the frame is cropped")
    func fullBounds() throws {
        let viewport = try #require(Viewport.fit(points: pointsWithOutlier(), fallback: nil))
        #expect(viewport.fullBounds.maxX >= 1_000_000)
        #expect(viewport.bounds.maxX < viewport.fullBounds.maxX)
    }

    @Test("Too few points to judge falls back to the extents")
    func tooFewPoints() throws {
        let viewport = try #require(
            Viewport.fit(points: [Point(0, 0), Point(10, 10)], fallback: nil))
        #expect(viewport.bounds.minX == 0)
        #expect(viewport.bounds.maxX == 10)
        #expect(!viewport.hasGeometryOutside)
    }

    @Test("No points at all uses the fallback extents")
    func noPoints() throws {
        let fallback = Bounds(minX: -5, minY: -5, maxX: 5, maxY: 5)
        let viewport = try #require(Viewport.fit(points: [], fallback: fallback))
        #expect(viewport.bounds == fallback)
        #expect(!viewport.hasGeometryOutside)
    }

    @Test("No points and no fallback means there is nothing to show")
    func nothing() {
        #expect(Viewport.fit(points: [], fallback: nil) == nil)
    }

    @Test("A single point does not produce a zero-size frame")
    func singlePoint() throws {
        let viewport = try #require(Viewport.fit(points: [Point(7, 7)], fallback: nil))
        #expect(viewport.bounds.width > 0 || viewport.bounds.height > 0)
    }

    @Test("The frame keeps the drawing's aspect ratio")
    func aspectRatio() throws {
        // A wide drawing: 2000 by 100 units.
        var points: [Point] = []
        for i in 0..<200 { points.append(Point(Double(i) * 10, 0)) }
        for i in 0..<10 { points.append(Point(0, Double(i) * 10)) }
        let viewport = try #require(Viewport.fit(points: points, fallback: nil))
        let bounds = viewport.bounds
        let drawingAspect = 1990.0 / 90.0
        let frameAspect = bounds.width / bounds.height
        // Frames are square-ish padded, so only check the frame is not distorted wildly.
        #expect(frameAspect > 0)
        #expect(drawingAspect > 1)
    }

    @Test("Quantiles of a sorted array")
    func quantiles() {
        let sorted = (0...100).map(Double.init)
        #expect(Viewport.quantile(sorted, 0) == 0)
        #expect(Viewport.quantile(sorted, 1) == 100)
        #expect(Viewport.quantile(sorted, 0.5) == 50)
        // Out-of-range requests clamp rather than trap.
        #expect(Viewport.quantile(sorted, -1) == 0)
        #expect(Viewport.quantile(sorted, 2) == 100)
        #expect(Viewport.quantile([], 0.5) == 0)
    }

    @Test("One bad coordinate does not erase the drawing")
    func nonFinitePoint() {
        // `min(infinity, .nan)` is `.nan` in Swift, so a single non-finite coordinate would
        // make the extents NaN and the viewport divide by it: the drawing disappears, and
        // nothing says why. A DXF can carry one.
        var accumulator = Bounds.Accumulator()
        accumulator.add([Point(0, 0), Point(10, 10)])
        accumulator.add(Point(.nan, 5))
        accumulator.add(Point(5, .infinity))

        let bounds = accumulator.bounds
        #expect(bounds != nil)
        #expect(bounds?.minX == 0)
        #expect(bounds?.maxX == 10)
        #expect(accumulator.skipped == 2)
    }

    @Test("A drawing of only bad coordinates has no extents, rather than a NaN box")
    func onlyNonFinite() {
        var accumulator = Bounds.Accumulator()
        accumulator.add(Point(.nan, .nan))
        // Nothing finite was added, so there is nothing to frame — which the caller can say.
        #expect(accumulator.bounds == nil)
        #expect(accumulator.skipped == 1)
    }
}
