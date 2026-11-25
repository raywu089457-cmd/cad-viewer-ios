import Testing
import SwiftDXF
@testable import DXFGeometry

/// Whether a parsed file holds anything the reader can see.
///
/// A truncated DXF is the case this exists for: its header survives, so the extents are present
/// and a viewport can be framed around them, and the app would otherwise show a blank canvas
/// and report the file as opened.
@Suite("Load readiness")
struct LoadReadinessTests {
    /// A header with extents but no entities, which is what a truncated file leaves.
    private var headerOnly: String {
        """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1009
        9
        $EXTMIN
        10
        0
        20
        0
        9
        $EXTMAX
        10
        100
        20
        100
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        ENDSEC
        0
        EOF
        """
    }

    @Test("A header with no entities parses, and has extents")
    func headerOnlyParses() throws {
        let drawing = try DXF.read(text: headerOnly)
        let scene = SceneBuilder().build(drawing)
        #expect(scene.samplePoints.isEmpty)
        // This is why an empty canvas looked like success: there are extents to frame.
        #expect(scene.bounds != nil)
    }

    @Test("And is reported as empty rather than drawable")
    func headerOnlyIsEmpty() throws {
        let drawing = try DXF.read(text: headerOnly)
        let scene = SceneBuilder().build(drawing)
        #expect(
            LoadReadiness.verdict(
                samplePoints: scene.samplePoints, hasBounds: scene.bounds != nil) == .empty)
    }

    @Test("A drawing with a line is drawable")
    func lineIsDrawable() throws {
        let source = """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1015
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        10
        0
        20
        0
        11
        10
        21
        10
        0
        ENDSEC
        0
        EOF
        """
        let scene = SceneBuilder().build(
            try DXF.read(text: source, options: DrawingReadOptions.app))
        #expect(
            LoadReadiness.verdict(
                samplePoints: scene.samplePoints, hasBounds: scene.bounds != nil) == .drawable)
    }

    @Test("Points without extents are not drawable")
    func pointsWithoutBounds() {
        #expect(
            LoadReadiness.verdict(samplePoints: [Point(0, 0)], hasBounds: false) == .empty)
    }

    @Test("Extents without points are not drawable")
    func boundsWithoutPoints() {
        #expect(LoadReadiness.verdict(samplePoints: [], hasBounds: true) == .empty)
    }

    @Test("Garbage is rejected by the reader rather than parsed")
    func garbage() {
        #expect((try? DXF.read(text: "hello world, not a drawing\n")) == nil)
    }
}
