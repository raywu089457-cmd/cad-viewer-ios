import Testing
@testable import DXFGeometry

/// The pan/zoom arithmetic, which is the part of a drawing viewer that cannot be eyeballed
/// from a screenshot.
@Suite("View transform")
struct ViewTransformTests {
    let portrait = ScreenSize(width: 390, height: 844)
    let square = Bounds(minX: 0, minY: 0, maxX: 1000, maxY: 1000)

    @Test("A fitted transform shows the whole drawing")
    func fitsWholeDrawing() {
        let transform = ViewTransform.fitting(square, in: portrait)

        // Every corner of the drawing lands inside the view.
        for corner in [
            Point(0, 0), Point(1000, 0), Point(0, 1000), Point(1000, 1000)
        ] {
            let screen = transform.screenPoint(for: corner)
            #expect(screen.x >= -0.001 && screen.x <= portrait.width + 0.001)
            #expect(screen.y >= -0.001 && screen.y <= portrait.height + 0.001)
        }
    }

    @Test("The fitted drawing is centred")
    func centering() {
        let transform = ViewTransform.fitting(square, in: portrait)
        let middle = transform.screenPoint(for: Point(500, 500))
        #expect(abs(middle.x - portrait.width / 2) < 0.001)
        #expect(abs(middle.y - portrait.height / 2) < 0.001)
    }

    @Test("Screen and drawing coordinates round-trip")
    func roundTrip() {
        let transform = ViewTransform.fitting(square, in: portrait)
        for screen in [
            ScreenPoint(x: 0, y: 0),
            ScreenPoint(x: 195, y: 422),
            ScreenPoint(x: 390, y: 844)
        ] {
            let drawing = transform.drawingPoint(at: screen)
            let back = transform.screenPoint(for: drawing)
            #expect(abs(back.x - screen.x) < 1e-9)
            #expect(abs(back.y - screen.y) < 1e-9)
        }
    }

    @Test("Zooming keeps the anchor point under the finger")
    func zoomKeepsAnchor() {
        var transform = ViewTransform.fitting(square, in: portrait)
        let anchor = ScreenPoint(x: 120, y: 700)
        let before = transform.drawingPoint(at: anchor)

        transform.zoom(by: 3, around: anchor)

        let after = transform.drawingPoint(at: anchor)
        #expect(abs(after.x - before.x) < 1e-6)
        #expect(abs(after.y - before.y) < 1e-6)
    }

    @Test("Zooming out then in returns to the same view")
    func zoomIsReversible() {
        var transform = ViewTransform.fitting(square, in: portrait)
        let anchor = ScreenPoint(x: 300, y: 200)
        let original = transform

        transform.zoom(by: 2.5, around: anchor)
        transform.zoom(by: 1 / 2.5, around: anchor)

        #expect(abs(transform.scale - original.scale) < 1e-9)
        #expect(abs(transform.center.x - original.center.x) < 1e-6)
        #expect(abs(transform.center.y - original.center.y) < 1e-6)
    }

    @Test("Panning moves the drawing with the finger")
    func panDirection() {
        var transform = ViewTransform.fitting(square, in: portrait)
        let start = transform.screenPoint(for: Point(0, 0))

        // Dragging right and down by 50 points.
        transform.pan(by: ScreenPoint(x: 50, y: 50))

        let moved = transform.screenPoint(for: Point(0, 0))
        #expect(abs(moved.x - (start.x + 50)) < 1e-9)
        #expect(abs(moved.y - (start.y + 50)) < 1e-9)
    }

    @Test("Zoom cannot escape its limits")
    func zoomLimits() {
        var transform = ViewTransform.fitting(square, in: portrait)
        let anchor = ScreenPoint(x: 195, y: 422)

        // A pinched-in gesture repeated far past any sane amount.
        for _ in 0..<200 { transform.zoom(by: 2, around: anchor) }
        let mostZoomedIn = transform.scale
        #expect(mostZoomedIn.isFinite && mostZoomedIn > 0)

        for _ in 0..<600 { transform.zoom(by: 0.5, around: anchor) }
        #expect(transform.scale.isFinite && transform.scale > 0)
        #expect(transform.scale > mostZoomedIn)
    }

    @Test("Resizing keeps the centre")
    func resizeKeepsCenter() {
        var transform = ViewTransform.fitting(square, in: portrait)
        let center = transform.center
        transform.resize(to: ScreenSize(width: 844, height: 390))
        #expect(transform.center == center)
        #expect(transform.viewSize.width == 844)
    }

    @Test("Visibility rejects what is off screen")
    func visibility() {
        var transform = ViewTransform.fitting(square, in: portrait)
        // Zoom into the bottom-left corner of the drawing.
        transform.zoom(by: 20, around: ScreenPoint(x: 0, y: portrait.height))

        #expect(transform.isVisible(Bounds(minX: 0, minY: 0, maxX: 10, maxY: 10)))
        #expect(!transform.isVisible(Bounds(minX: 990, minY: 990, maxX: 1000, maxY: 1000)))
    }

    @Test("A zero-size or single-point drawing does not divide by zero")
    func degenerateBounds() {
        let point = Bounds(minX: 5, minY: 5, maxX: 5, maxY: 5)
        let transform = ViewTransform.fitting(point, in: portrait)
        #expect(transform.scale.isFinite && transform.scale > 0)
        #expect(transform.center == Point(5, 5))

        let zeroView = ViewTransform.fitting(square, in: ScreenSize(width: 0, height: 0))
        #expect(zeroView.scale.isFinite && zeroView.scale > 0)
    }
}
