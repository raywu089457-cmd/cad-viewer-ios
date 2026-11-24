import Testing
import SwiftDXF
@testable import DXFGeometry

/// The options the app opens drawings with, and the tests now share.
///
/// These settings are not incidental: they decide whether block geometry appears at all,
/// whether paper space is drawn, and whether the part numbers on a block are visible. A test
/// suite that used the defaults would be checking a configuration the app never runs.
@Suite("Drawing read options")
struct DrawingReadOptionsTests {
    @Test("The app expands blocks, or a plan is just its top-level lines")
    func expandsBlocks() {
        #expect(DrawingReadOptions.app.expandBlocks)
    }

    @Test("The app skips paper space, because model space is the drawing")
    func skipsPaperSpace() {
        #expect(DrawingReadOptions.app.skipPaperSpace)
    }

    @Test("The app expands attributes, or blocks have no labels")
    func expandsAttributes() {
        #expect(DrawingReadOptions.app.expandAttributes)
    }

    @Test("The bare options are the library defaults, for tests about those")
    func bare() {
        #expect(!DrawingReadOptions.bare.expandBlocks)
        #expect(!DrawingReadOptions.bare.skipPaperSpace)
        #expect(!DrawingReadOptions.bare.expandAttributes)
    }
}
