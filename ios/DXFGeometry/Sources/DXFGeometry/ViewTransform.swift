import Foundation

/// A size in screen points.
///
/// Deliberately not `CGSize`: this type has to compile and be unit-tested on platforms
/// without CoreGraphics, and the pan/zoom arithmetic is the part most worth testing.
public struct ScreenSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    var isValid: Bool { width > 0 && height > 0 && width.isFinite && height.isFinite }
}

/// A point in screen space, y pointing down.
public struct ScreenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The mapping between drawing coordinates and screen coordinates, plus the operations
/// that change it.
///
/// Keeping this out of the view makes the arithmetic testable. Pan and zoom bugs are the
/// kind that only show up under a finger on a device, so it is worth being able to reason
/// about them directly.
///
/// Drawing space has y pointing up; screen space has y pointing down. The flip happens
/// here and nowhere else.
public struct ViewTransform: Equatable, Sendable {
    /// Screen points per drawing unit. Larger means more zoomed in.
    ///
    /// Using points-per-unit (rather than units-per-point) is what makes the fit formula
    /// and the gestures read the same way: zooming in multiplies, zooming out divides.
    public var scale: Double
    /// The drawing point shown at the centre of the view.
    public var center: Point
    /// The size of the view in screen points.
    public var viewSize: ScreenSize

    public init(scale: Double, center: Point, viewSize: ScreenSize) {
        self.scale = scale
        self.center = center
        self.viewSize = viewSize
    }

    /// Zoom limits as a fraction (and multiple) of the scale that fits a unit square.
    ///
    /// At the low end the whole of a site plan is a thumbnail; at the high end one drawing
    /// unit covers 200 points, enough to line up a detail.
    static let minRelativeZoom: Double = 1.0 / 2000
    static let maxRelativeZoom: Double = 200

    /// The middle of two numbers, computed without adding them.
    ///
    /// `(a + b) / 2` overflows when both are large, and a DXF can carry coordinates that large.
    /// Half of each, plus half of the difference, stays finite whenever the inputs are.
    static func midpoint(_ a: Double, _ b: Double) -> Double {
        a / 2 + b / 2
    }

    /// A transform that fits `bounds` inside `viewSize` with a small margin.
    public static func fitting(
        _ bounds: Bounds,
        in viewSize: ScreenSize,
        margin: Double = 0.04
    ) -> ViewTransform {
        let width = max(viewSize.width, 1)
        let height = max(viewSize.height, 1)
        // A drawing can be a single point or a single line, so guard every division.
        let drawingWidth = max(bounds.width, .ulpOfOne)
        let drawingHeight = max(bounds.height, .ulpOfOne)
        let usable = max(1 - margin * 2, 0.1)
        let candidate = min(width * usable / drawingWidth, height * usable / drawingHeight)
        let scale = candidate.isFinite && candidate > 0 ? candidate : 1
        return ViewTransform(
            scale: scale,
            // `(minX + maxX) / 2` overflows when both corners are large: `1e308 + 1e308` is
            // infinity, and an infinite centre puts the whole drawing off screen even though the
            // corners themselves are finite. This form cannot overflow.
            center: Point(
                Self.midpoint(bounds.minX, bounds.maxX),
                Self.midpoint(bounds.minY, bounds.maxY)
            ),
            viewSize: ScreenSize(width: width, height: height)
        )
    }

    /// The drawing point under a screen point.
    public func drawingPoint(at screen: ScreenPoint) -> Point {
        Point(
            center.x + (screen.x - viewSize.width / 2) / scale,
            // Screen y grows down, drawing y grows up.
            center.y - (screen.y - viewSize.height / 2) / scale
        )
    }

    /// The screen point for a drawing point.
    public func screenPoint(for drawing: Point) -> ScreenPoint {
        ScreenPoint(
            x: (drawing.x - center.x) * scale + viewSize.width / 2,
            y: (center.y - drawing.y) * scale + viewSize.height / 2
        )
    }

    /// Whether a drawing rectangle is at least partly on screen.
    ///
    /// Building a path for every primitive while zoomed into one detail is the difference
    /// between smooth and unusable, so the renderer asks this first.
    public func isVisible(_ rect: Bounds) -> Bool {
        let topLeft = drawingPoint(at: ScreenPoint(x: 0, y: 0))
        let bottomRight = drawingPoint(
            at: ScreenPoint(x: viewSize.width, y: viewSize.height))
        let minX = min(topLeft.x, bottomRight.x)
        let maxX = max(topLeft.x, bottomRight.x)
        let minY = min(topLeft.y, bottomRight.y)
        let maxY = max(topLeft.y, bottomRight.y)
        return rect.maxX >= minX && rect.minX <= maxX
            && rect.maxY >= minY && rect.minY <= maxY
    }

    /// Scales by `factor`, keeping the drawing point under `anchor` fixed.
    ///
    /// Pinning the anchor is what makes a pinch feel attached to the fingers instead of
    /// drifting towards the centre of the screen.
    public mutating func zoom(by factor: Double, around anchor: ScreenPoint) {
        guard factor.isFinite, factor > 0, factor != 1 else { return }
        let before = drawingPoint(at: anchor)
        let limits = scaleLimits
        let clamped = min(max(scale * factor, limits.lowerBound), limits.upperBound)
        guard clamped != scale else { return }
        scale = clamped
        // Put the same drawing point back under the anchor.
        let after = drawingPoint(at: anchor)
        center = Point(
            center.x + (before.x - after.x),
            center.y + (before.y - after.y)
        )
    }

    /// Pans by a screen-space translation.
    public mutating func pan(by translation: ScreenPoint) {
        guard translation.x.isFinite, translation.y.isFinite else { return }
        center = Point(
            center.x - translation.x / scale,
            // Dragging down moves the drawing down, which moves the centre up.
            center.y + translation.y / scale
        )
    }

    /// The allowed scale, anchored to the fit scale of a unit square so the limits mean the
    /// same thing on any display and at any drawing size.
    private var scaleLimits: ClosedRange<Double> {
        let reference = ViewTransform.fitting(
            Bounds(minX: 0, minY: 0, maxX: 1, maxY: 1),
            in: viewSize
        ).scale
        let lower = max(reference * ViewTransform.minRelativeZoom, .ulpOfOne)
        let upper = max(reference * ViewTransform.maxRelativeZoom, lower)
        return lower...upper
    }

    /// Updates the viewport size, keeping the same drawing point centred.
    public mutating func resize(to newSize: ScreenSize) {
        guard newSize.isValid, newSize != viewSize else { return }
        viewSize = newSize
    }
}
