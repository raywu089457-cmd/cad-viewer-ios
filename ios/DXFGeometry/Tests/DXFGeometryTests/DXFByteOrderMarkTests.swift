import Foundation
import Testing

@testable import DXFGeometry

@Suite("A byte-order mark before the first group code")
struct DXFByteOrderMarkTests {
    /// A minimal ASCII DXF with one line, as bytes.
    private var clean: Data {
        [
            "0", "SECTION", "2", "ENTITIES",
            "0", "LINE", "8", "0", "10", "0", "20", "0", "11", "10", "21", "5",
            "0", "ENDSEC", "0", "EOF",
        ].joined(separator: "\n").data(using: .utf8)!
    }

    private var marked: Data {
        Data(DXFByteOrderMark.utf8) + clean
    }

    @Test("The mark is three bytes and is found only when it is there")
    func detection() {
        #expect(DXFByteOrderMark.utf8 == [0xEF, 0xBB, 0xBF])
        #expect(DXFByteOrderMark.present(in: marked))
        #expect(!DXFByteOrderMark.present(in: clean))
    }

    @Test("An empty or tiny file has no mark to find")
    func tooShort() {
        #expect(!DXFByteOrderMark.present(in: Data()))
        #expect(!DXFByteOrderMark.present(in: Data([0xEF])))
        #expect(!DXFByteOrderMark.present(in: Data([0xEF, 0xBB])))
    }

    @Test("Stripping removes exactly the mark and nothing else")
    func stripping() {
        #expect(DXFByteOrderMark.stripping(from: marked) == clean)
        #expect(DXFByteOrderMark.stripping(from: clean) == clean)
        #expect(DXFByteOrderMark.stripping(from: Data()) == Data())
    }

    @Test("Only the UTF-8 mark is removed")
    func otherEncodings() {
        // A UTF-16 file is not ASCII DXF. Dropping its first bytes would leave something worse
        // than a clear failure, so the mark stays and the reader says what it thinks.
        var utf16Mark = Data([0xFF, 0xFE])
        utf16Mark.append(contentsOf: Array("0\nEOF".utf16.flatMap { withUnsafeBytes(of: $0) { Array($0) } }))
        #expect(!DXFByteOrderMark.present(in: utf16Mark))
        #expect(DXFByteOrderMark.stripping(from: utf16Mark) == utf16Mark)
    }
}
