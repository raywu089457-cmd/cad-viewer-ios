import Testing
import Foundation
import SwiftDXF
@testable import DXFGeometry

/// Checks the flattening against hand-built DXF, so a regression shows up as a failing
/// expectation rather than as a drawing that merely looks odd.
@Suite("Scene builder")
struct SceneBuilderTests {
    /// A minimal ASCII DXF with the given ENTITIES section body.
    static func dxf(_ entities: String, extents: (Double, Double, Double, Double)? = nil) -> String {
        let header: String
        if let (minX, minY, maxX, maxY) = extents {
            header = """
            0
            SECTION
            2
            HEADER
            9
            $EXTMIN
            10
            \(minX)
            20
            \(minY)
            9
            $EXTMAX
            10
            \(maxX)
            20
            \(maxY)
            0
            ENDSEC
            """
        } else {
            header = ""
        }
        return """
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
        \(header)
        0
        SECTION
        2
        ENTITIES
        \(entities)
        0
        ENDSEC
        0
        EOF
        """
    }

    static func build(_ entities: String, extents: (Double, Double, Double, Double)? = nil)
        throws -> DrawScene
    {
        let drawing = try DXF.read(text: dxf(entities, extents: extents))
        return SceneBuilder().build(drawing)
    }

    @Test("A LINE becomes one two-point polyline")
    func line() throws {
        let scene = try Self.build("""
        0
        LINE
        8
        Walls
        10
        0
        20
        0
        11
        10
        21
        5
        """)
        #expect(scene.polylines.count == 1)
        let line = try #require(scene.polylines.first)
        #expect(line.layer == "Walls")
        #expect(line.points.count == 2)
        #expect(line.points[0] == Point(0, 0))
        #expect(line.points[1] == Point(10, 5))
        #expect(!line.isClosed)
    }

    @Test("A CIRCLE becomes a closed run that stays on the radius")
    func circle() throws {
        let scene = try Self.build("""
        0
        CIRCLE
        8
        0
        10
        100
        20
        50
        40
        25
        """)
        let circle = try #require(scene.polylines.first)
        #expect(circle.isClosed)
        #expect(circle.points.count >= 17)
        // Every point is on the circle, and the run closes back onto the start.
        for point in circle.points {
            let radius = (point.x - 100) * (point.x - 100) + (point.y - 50) * (point.y - 50)
            #expect(abs(radius.squareRoot() - 25) < 1e-9)
        }
        let first = try #require(circle.points.first)
        let last = try #require(circle.points.last)
        #expect(abs(first.x - last.x) < 1e-9)
        #expect(abs(first.y - last.y) < 1e-9)
    }

    @Test("An ARC goes the short way round when it is written that way")
    func arcSweep() throws {
        // A quarter circle from 0 to 90 degrees, counter-clockwise.
        let scene = try Self.build("""
        0
        ARC
        8
        0
        10
        0
        20
        0
        40
        10
        50
        0
        51
        90
        """)
        let arc = try #require(scene.polylines.first)
        #expect(!arc.isClosed)
        let first = try #require(arc.points.first)
        let last = try #require(arc.points.last)
        #expect(abs(first.x - 10) < 1e-9)
        #expect(abs(first.y) < 1e-9)
        #expect(abs(last.x) < 1e-9)
        #expect(abs(last.y - 10) < 1e-9)
    }

    @Test("A bulge becomes an arc, not a straight chord")
    func polylineBulge() throws {
        // A semicircle from (0,0) to (10,0): bulge 1 is a half turn.
        let scene = try Self.build("""
        0
        LWPOLYLINE
        8
        0
        90
        2
        70
        0
        10
        0
        20
        0
        42
        1
        10
        10
        20
        0
        """)
        let path = try #require(scene.polylines.first)
        #expect(path.points.count > 4)
        // The arc bulges away from the chord, so some point sits well off the x axis.
        let highest = path.points.map(\.y).max() ?? 0
        #expect(abs(highest - 5) < 0.05)
    }

    @Test("TEXT keeps its position, height and string")
    func text() throws {
        let scene = try Self.build("""
        0
        TEXT
        8
        Labels
        10
        20
        20
        30
        40
        20
        1
        Room 101
        """)
        let text = try #require(scene.texts.first)
        #expect(text.string == "Room 101")
        #expect(text.position == Point(20, 40))
        #expect(text.height == 20)
        #expect(text.layer == "Labels")
    }

    @Test("A layer colour is inherited by entities drawn ByLayer")
    func layerColor() throws {
        let drawing = try DXF.read(text: """
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
        TABLES
        0
        TABLE
        2
        LAYER
        0
        LAYER
        2
        Red
        70
        0
        62
        1
        6
        CONTINUOUS
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        Red
        10
        0
        20
        0
        11
        1
        21
        1
        0
        ENDSEC
        0
        EOF
        """)
        let scene = SceneBuilder().build(drawing)
        let line = try #require(scene.polylines.first)
        // ACI 1 is red.
        #expect(line.color.r > 0.9)
        #expect(line.color.g < 0.1)
        #expect(line.color.b < 0.1)
    }

    @Test("Bounds cover the geometry")
    func bounds() throws {
        let scene = try Self.build("""
        0
        LINE
        10
        -5
        20
        -7
        11
        15
        21
        23
        """)
        let bounds = try #require(scene.bounds)
        #expect(bounds.minX == -5)
        #expect(bounds.minY == -7)
        #expect(bounds.maxX == 15)
        #expect(bounds.maxY == 23)
    }

    @Test("An empty drawing yields no primitives rather than crashing")
    func empty() throws {
        let scene = try Self.build("")
        #expect(scene.polylines.isEmpty)
        #expect(scene.texts.isEmpty)
    }
}

/// The ACI palette, which is easy to get subtly wrong.
@Suite("ACI colours")
struct ACIColourTests {
    @Test("The fixed entries")
    func fixedEntries() {
        #expect(ACI.rgb(1) == RGB(1, 0, 0))
        #expect(ACI.rgb(5) == RGB(0, 0, 1))
        #expect(ACI.rgb(8).r == 0.5 && ACI.rgb(8).g == 0.5)
    }

    @Test("Index 7 follows the background")
    func indexSeven() {
        #expect(ACI.rgb(7, onDarkBackground: true) == RGB(1, 1, 1))
        #expect(ACI.rgb(7, onDarkBackground: false) == RGB(0, 0, 0))
    }

    @Test("Generated hues stay inside the colour cube")
    func generatedRange() {
        for index in 10...249 {
            let color = ACI.rgb(index)
            for component in [color.r, color.g, color.b] {
                #expect(component >= 0 && component <= 1)
            }
        }
    }

    @Test("Different indices give different colours")
    func distinct() {
        let colors = (1...9).map { ACI.rgb($0) }
        #expect(Set(colors.map { "\($0.r),\($0.g),\($0.b)" }).count == 9)
    }
}

/// The cached extents the renderer culls with. Getting them wrong means a primitive that is
/// on screen gets skipped, or one that is not gets drawn every frame.
@Suite("Primitive bounds")
struct PrimitiveBoundsTests {
    @Test("A polyline's cached bounds cover its points")
    func polylineBounds() throws {
        let scene = try SceneBuilderTests.build("""
        0
        LINE
        10
        -5
        20
        -7
        11
        15
        21
        23
        """)
        let line = try #require(scene.polylines.first)
        #expect(line.bounds.minX == -5)
        #expect(line.bounds.minY == -7)
        #expect(line.bounds.maxX == 15)
        #expect(line.bounds.maxY == 23)
    }

    @Test("A circle's cached bounds are its box, not its points")
    func circleBounds() throws {
        let scene = try SceneBuilderTests.build("""
        0
        CIRCLE
        10
        100
        20
        50
        40
        25
        """)
        let circle = try #require(scene.polylines.first)
        #expect(circle.bounds.minX >= 75 - 1e-9)
        #expect(circle.bounds.maxX <= 125 + 1e-9)
        #expect(circle.bounds.minY >= 25 - 1e-9)
        #expect(circle.bounds.maxY <= 75 + 1e-9)
    }

    @Test("A hatch fill's cached bounds cover its outer loop")
    func fillBounds() throws {
        let scene = try SceneBuilderTests.build("""
        0
        SOLID
        10
        0
        20
        0
        11
        10
        21
        0
        12
        0
        22
        10
        13
        10
        23
        10
        """)
        let fill = try #require(scene.fills.first)
        #expect(fill.bounds.minX == 0)
        #expect(fill.bounds.minY == 0)
        #expect(fill.bounds.maxX == 10)
        #expect(fill.bounds.maxY == 10)
    }
}

/// The curve tolerance, which decides how smooth every arc looks.
@Suite("Curve tolerance")
struct CurveToleranceTests {
    /// Segments in a lone circle, optionally with header extents supplied.
    private func circleSegments(radius: Double, withHeader: Bool) -> Int {
        var header = ""
        if withHeader {
            header = """
            9
            $EXTMIN
            10
            \(-radius)
            20
            \(-radius)
            9
            $EXTMAX
            10
            \(radius)
            20
            \(radius)
            """
        }
        let source = """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1015
        \(header)
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        CIRCLE
        10
        0
        20
        0
        40
        \(radius)
        0
        ENDSEC
        0
        """
        guard let drawing = try? DXF.read(text: source) else { return -1 }
        return SceneBuilder().build(drawing).polylines.first?.points.count ?? -1
    }

    @Test("A missing header gives the same tessellation as a present one")
    func headerIndependence() {
        // R12 files usually have no $EXTMIN, so the tolerance has to be measured, not read.
        let without = circleSegments(radius: 1_000_000, withHeader: false)
        let with = circleSegments(radius: 1_000_000, withHeader: true)
        #expect(without == with)
        #expect(without > 16)
    }

    @Test("The same circle tessellates the same at any scale")
    func scaleInvariance() {
        // The tolerance is a fraction of the drawing size, so a circle looks equally smooth
        // in a millimetre drawing and a metre one.
        let tiny = circleSegments(radius: 0.5, withHeader: false)
        let huge = circleSegments(radius: 1_000_000, withHeader: false)
        #expect(abs(tiny - huge) <= 2)
    }

    @Test("A full circle stays within the segment cap")
    func bounded() {
        let huge = circleSegments(radius: 1_000_000, withHeader: false)
        #expect(huge <= 60)
    }
}
