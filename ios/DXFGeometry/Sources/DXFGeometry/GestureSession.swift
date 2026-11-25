import Foundation

/// A gesture's transform arithmetic, kept apart from the view.
///
/// A drag and a pinch both apply a delta to the transform as it was when the gesture began,
/// not to the previous frame: applying frame-by-frame deltas compounds rounding and the
/// drawing drifts away from the finger. Both gestures are live at once too, so each needs its
/// own base — sharing one made the second gesture start from a stale transform the moment the
/// first ended, which is a bug this file exists to keep fixed.
///
/// The arithmetic is here, where it is testable, rather than in a `some Gesture` closure.
public struct GestureSession: Equatable, Sendable {
    /// The transform the current gesture started from, or `nil` between gestures.
    private var base: ViewTransform?

    public init() {}

    /// The transform to apply a delta to, capturing the current one on first use.
    ///
    /// - Parameter current: the view's transform, used when no gesture is in progress.
    public mutating func origin(_ current: ViewTransform) -> ViewTransform {
        if let base { return base }
        base = current
        return current
    }

    /// Ends the gesture, so the next one captures a fresh origin.
    public mutating func end() {
        base = nil
    }

    /// Whether a gesture is in progress.
    public var isActive: Bool { base != nil }

    /// A dragged update.
    ///
    /// - Parameters:
    ///   - current: the view's transform.
    ///   - translation: the drag in screen points, in the same sign space as `DragGesture`.
    public mutating func pan(
        _ current: ViewTransform, by translation: ScreenPoint
    ) -> ViewTransform {
        var next = origin(current)
        next.pan(by: translation)
        return next
    }

    /// A magnified update.
    ///
    /// - Parameters:
    ///   - current: the view's transform.
    ///   - magnification: the pinch factor, as `MagnifyGesture` reports it.
    ///   - startAnchor: the pinch midpoint, normalised to `0...1` across the view.
    public mutating func zoom(
        _ current: ViewTransform,
        by magnification: Double,
        at startAnchor: ScreenPoint
    ) -> ViewTransform {
        var next = origin(current)
        // The anchor arrives normalised, so it is scaled back to screen points.
        let anchor = ScreenPoint(
            x: startAnchor.x * next.viewSize.width,
            y: startAnchor.y * next.viewSize.height
        )
        next.zoom(by: magnification, around: anchor)
        return next
    }
}
