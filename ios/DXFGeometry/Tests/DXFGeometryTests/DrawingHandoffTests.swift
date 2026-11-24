import Testing
@testable import DXFGeometry

/// How a drawing is handed to an already-loaded page. Direct keeps the wasm engine warm;
/// a reload always works but costs a re-initialise. Getting this wrong on a large file means
/// a slow JavaScript call, or one the web view refuses outright.
@Suite("Drawing handoff")
struct DrawingHandoffTests {
    @Test("A small drawing with a capable page goes directly")
    func directly() {
        #expect(DrawingHandoff(byteCount: 1000, pageCanAcceptDirectly: true) == .directly)
    }

    @Test("The limit is inclusive")
    func limitBoundary() {
        #expect(
            DrawingHandoff(byteCount: DrawingHandoff.directLimit, pageCanAcceptDirectly: true)
                == .directly)
        #expect(
            DrawingHandoff(
                byteCount: DrawingHandoff.directLimit + 1, pageCanAcceptDirectly: true)
                == .viaReload)
    }

    @Test("A page without the entry point means a reload")
    func incapablePage() {
        #expect(DrawingHandoff(byteCount: 1, pageCanAcceptDirectly: false) == .viaReload)
    }

    @Test("A large drawing reloads, because base64 adds a third")
    func largeDrawing() {
        // Real DWG files are routinely tens of megabytes.
        #expect(
            DrawingHandoff(byteCount: 40 * 1024 * 1024, pageCanAcceptDirectly: true)
                == .viaReload)
    }
}
