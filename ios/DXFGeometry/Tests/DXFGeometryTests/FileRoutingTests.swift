import Testing
import Foundation
@testable import DXFGeometry

/// The routing decision, which is what sends a file to the native reader, the web view or
/// the system PDF reader. Getting it wrong means a blank canvas instead of an error.
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

    @Test("A dotted name uses the last component")
    func dottedName() {
        #expect(DrawingKind(fileName: "floor.plan.v2.dxf") == .dxf)
        #expect(DrawingKind(fileName: "report.final.pdf") == .pdf)
    }

    @Test("Other files are rejected with their extension")
    func rejects() {
        #expect(DrawingKind(fileName: "notes.txt") == .unsupported(extension: "txt"))
        #expect(!DrawingKind(fileName: "notes.txt").canRender)
        #expect(DrawingKind(fileName: "notes.txt").fileExtension == "txt")
    }

    @Test("A name with no extension is rejected without crashing")
    func noExtension() {
        let kind = DrawingKind(fileName: "README")
        #expect(kind == .unsupported(extension: ""))
        #expect(!kind.canRender)
        #expect(kind.fileExtension.isEmpty)
    }

    @Test("A leading dot is part of the name, not an extension")
    func dotfile() {
        // Foundation's own rule: ".dxf" has no extension, so the app refuses it rather than
        // guessing what was meant.
        #expect(DrawingKind(fileName: ".dxf") == .unsupported(extension: ""))
    }

    @Test("The extension comes back out unchanged")
    func extensionRoundTrip() {
        #expect(DrawingKind(fileName: "a.dxf").fileExtension == "dxf")
        #expect(DrawingKind(fileName: "a.dwg").fileExtension == "dwg")
        #expect(DrawingKind(fileName: "a.pdf").fileExtension == "pdf")
    }
}

/// The messages a reader actually sees.
@Suite("Load failure")
struct LoadFailureTests {
    @Test("An unsupported type names its extension")
    func unsupported() {
        let failure = LoadFailure(fileName: "a.step", reason: .unsupportedType("step"))
        #expect(failure.message == ".step files cannot be shown here.")
        #expect(failure.title == "Could not open a.step")
    }

    @Test("A file with no extension is explained, not named")
    func noExtension() {
        let failure = LoadFailure(fileName: "README", reason: .unsupportedType(""))
        #expect(failure.message.contains("no extension"))
    }

    @Test("Each reason reads as something to do next")
    func reasons() {
        #expect(LoadFailure(fileName: "a.dxf", reason: .empty).message == "The file is empty.")
        #expect(
            LoadFailure(fileName: "a.dxf", reason: .binaryDXF)
                .message.contains("binary DXF"))
        #expect(
            LoadFailure(fileName: "a.dxf", reason: .noGeometry)
                .message.contains("no model-space geometry"))
    }

    @Test("A parser's own detail is passed through")
    func unreadable() {
        let failure = LoadFailure(fileName: "a.dxf", reason: .unreadable("bad group code"))
        #expect(failure.message == "bad group code")
    }

    @Test("A failure with no file name still has a title")
    func anonymous() {
        let failure = LoadFailure(fileName: "", reason: .empty)
        #expect(failure.title == "Could not open the file")
    }

    @Test("Each failure has its own identity, so a repeat alert still shows")
    func identity() {
        let a = LoadFailure(fileName: "a.dxf", reason: .empty)
        let b = LoadFailure(fileName: "a.dxf", reason: .empty)
        #expect(a.id != b.id)
        #expect(a.reason == b.reason)
    }
}

/// The only format check the DWG path can have.
///
/// The bundled engine accepts any bytes and reports that it drew them, so a text file renamed to
/// `.dwg` opens to a blank canvas presented as a drawing. Every DWG begins with `AC` and a real
/// version number, which is cheap to confirm before handing the bytes over.
@Suite("DWG version header")
struct DWGHeaderTests {
    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    @Test("The three formats in the samples are recognised")
    func realVersions() {
        #expect(DWGHeader.version(of: bytes("AC1015")) == "AC1015")
        #expect(DWGHeader.version(of: bytes("AC1027")) == "AC1027")
        #expect(DWGHeader.version(of: bytes("AC1032")) == "AC1032")
    }

    @Test("Prose is not a drawing")
    func prose() {
        #expect(!DWGHeader.looksLikeDWG(bytes("This is not a drawing")))
    }

    @Test("A word that starts with AC is not a version")
    func looksLikeAC() {
        #expect(!DWGHeader.looksLikeDWG(bytes("ACME Corporation")))
    }

    @Test("A version outside the range AutoCAD used is refused")
    func outOfRange() {
        #expect(!DWGHeader.looksLikeDWG(bytes("AC9999")))
        #expect(!DWGHeader.looksLikeDWG(bytes("AC1000")))
    }

    @Test("Short and empty input is not a DWG")
    func short() {
        #expect(!DWGHeader.looksLikeDWG(Data()))
        #expect(!DWGHeader.looksLikeDWG(bytes("AC1")))
    }

    @Test("Letters after AC are not a version")
    func letters() {
        #expect(!DWGHeader.looksLikeDWG(bytes("AC10AB")))
    }

    @Test("A name with stray whitespace still has an engine")
    func strayWhitespace() {
        // Trailing whitespace survives download, cloud sync and copy-paste. Without a trim,
        // `pathExtension` answers "dxf " and the app refuses an ordinary file.
        #expect(DrawingKind(fileName: "plan.dxf ").canRender)
        #expect(DrawingKind(fileName: "  plan.dxf").canRender)
        #expect(DrawingKind(fileName: "plan.dxf\n").canRender)
        #expect(DrawingKind(fileName: "plan.dwg\t").canRender)

        // Trimming must not promote a type the app cannot draw.
        #expect(!DrawingKind(fileName: "notes.txt ").canRender)
    }

    @Test("A non-ASCII name routes on its extension, not its stem")
    func nonASCIIStem() {
        #expect(DrawingKind(fileName: "圖面-2024.dxf").canRender)
        #expect(DrawingKind(fileName: "圖面-2024.dxf").fileExtension == "dxf")
        #expect(DrawingKind(fileName: "план.dwg").canRender)
    }
}