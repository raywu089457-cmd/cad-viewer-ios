import Testing
@testable import DXFGeometry

/// A gesture's transform arithmetic, kept out of the view where it can be tested.
///
/// A drag and a pinch both apply their delta to the transform as it was when the gesture
/// began, not to the previous frame: frame-by-frame deltas compound rounding and the drawing
/// drifts away from the finger. Both gestures are live at once too, so each needs its own
/// origin — sharing one made the second start from a stale transform when the first ended.
@Suite("Gesture session")
struct GestureSessionTests {
    private let size = ScreenSize(width: 390, height: 844)
    private var fitted: ViewTransform {
        ViewTransform.fitting(
            Bounds(minX: 0, minY: 0, maxX: 1000, maxY: 1000), in: size)
    }

    @Test("A dragged update is measured from the gesture's origin")
    func panFromOrigin() {
        var session = GestureSession()
        let first = session.pan(fitted, by: ScreenPoint(x: 10, y: 0))
        let second = session.pan(first, by: ScreenPoint(x: 10, y: 0))
        // Both updates carry the same total translation, so both land in the same place.
        #expect(second == first)
    }

    @Test("The origin is captured once and released on end")
    func originLifetime() {
        var session = GestureSession()
        #expect(!session.isActive)
        _ = session.pan(fitted, by: ScreenPoint(x: 5, y: 0))
        #expect(session.isActive)
        session.end()
        #expect(!session.isActive)
    }

    @Test("Each gesture keeps its own origin")
    func separateSessions() {
        // The bug this guards: both gestures are live at once.
        var panSession = GestureSession()
        var pinchSession = GestureSession()
        _ = panSession.pan(fitted, by: ScreenPoint(x: 20, y: 0))
        let zoomed = pinchSession.zoom(fitted, by: 2, at: ScreenPoint(x: 0.5, y: 0.5))
        #expect(zoomed.scale != fitted.scale)

        panSession.end()
        // A further pinch update still multiplies its own origin, undisturbed by the drag.
        let later = pinchSession.zoom(zoomed, by: 1.1, at: ScreenPoint(x: 0.5, y: 0.5))
        #expect(abs(later.scale - fitted.scale * 1.1) < 1e-9)
    }

    @Test("Magnification is the total factor, so updates multiply the same origin")
    func magnificationIsCumulative() {
        var session = GestureSession()
        let first = session.zoom(fitted, by: 1.5, at: ScreenPoint(x: 0.5, y: 0.5))
        let second = session.zoom(first, by: 3, at: ScreenPoint(x: 0.5, y: 0.5))
        #expect(abs(second.scale - fitted.scale * 3) < 1e-9)
    }

    @Test("A pinch anchor is normalised to a fraction of the view")
    func normalisedAnchor() {
        var session = GestureSession()
        let zoomed = session.zoom(fitted, by: 4, at: ScreenPoint(x: 0, y: 1))
        #expect(zoomed.scale > fitted.scale)
        #expect(zoomed.scale.isFinite && zoomed.scale > 0)
    }

    @Test("A factor of one leaves the transform alone")
    func identity() {
        var session = GestureSession()
        #expect(session.zoom(fitted, by: 1, at: ScreenPoint(x: 0.5, y: 0.5)) == fitted)
    }
}
