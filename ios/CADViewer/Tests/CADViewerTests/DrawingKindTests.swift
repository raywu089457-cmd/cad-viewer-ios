import Testing
@testable import CADViewer

/// The routing decision, which is what sends a file to the native reader, the web view or
/// the system PDF reader.
@Suite("Drawing kind")
struct DrawingKindTests {
    @Test("DXF, DWG and PDF are recognised regardless of case")
    func recognises() {
        #expect(DrawingKind(fileName: "plan.dxf") == .dxf)
        #expect(DrawingKind(fileName: "plan.DXF") == .dxf)
        #expect(DrawingKind(fileName: "site.dwg") == .dwg)
        #expect(DrawingKind(fileName: "site.Dwg") == .dwg)
        #expect(DrawingKind(fileName: "sheet.pdf") == .pdf)
        #expect(DrawingKind(fileName: "sheet.PDF") == .pdf)
    }

    @Test("Every recognised type can be rendered")
    func rendersWhatItRecognises() {
        for name in ["a.dxf", "a.dwg", "a.pdf"] {
            #expect(DrawingKind(fileName: name).canRender, "\(name) should be shown")
        }
    }

    @Test("Other files are rejected with their extension")
    func rejects() {
        #expect(DrawingKind(fileName: "notes.txt") == .unsupported(extension: "txt"))
        #expect(!DrawingKind(fileName: "notes.txt").canRender)
    }

    @Test("A file with no extension is handled without crashing")
    func noExtension() {
        let kind = DrawingKind(fileName: "README")
        #expect(!kind.canRender)
    }

    @Test("A dotted name uses the last component")
    func dottedName() {
        #expect(DrawingKind(fileName: "floor.plan.v2.dxf") == .dxf)
        #expect(DrawingKind(fileName: "report.final.pdf") == .pdf)
    }
}
