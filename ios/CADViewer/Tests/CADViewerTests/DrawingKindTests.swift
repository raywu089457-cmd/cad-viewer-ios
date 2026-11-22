import Testing
@testable import CADViewer

/// The routing decision, which is what sends a file to the native reader or the web view.
@Suite("Drawing kind")
struct DrawingKindTests {
    @Test("DXF and DWG are recognised regardless of case")
    func recognises() {
        #expect(DrawingKind(fileName: "plan.dxf") == .dxf)
        #expect(DrawingKind(fileName: "plan.DXF") == .dxf)
        #expect(DrawingKind(fileName: "site.dwg") == .dwg)
        #expect(DrawingKind(fileName: "site.Dwg") == .dwg)
    }

    @Test("Other files are rejected with their extension")
    func rejects() {
        #expect(DrawingKind(fileName: "notes.pdf") == .unsupported(extension: "pdf"))
        #expect(!DrawingKind(fileName: "notes.pdf").canRender)
        #expect(DrawingKind(fileName: "notes.pdf") != .dxf)
    }

    @Test("A file with no extension is handled without crashing")
    func noExtension() {
        let kind = DrawingKind(fileName: "README")
        #expect(!kind.canRender)
    }

    @Test("A dotted name uses the last component")
    func dottedName() {
        #expect(DrawingKind(fileName: "floor.plan.v2.dxf") == .dxf)
    }
}
