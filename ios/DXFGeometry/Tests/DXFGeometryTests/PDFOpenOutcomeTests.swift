import Testing

@testable import DXFGeometry

/// A PDF can fail in two ways that look the same to a reader — a file that is not a PDF, and
/// one that is but holds nothing — and the viewer says which. The decision is here so the
/// message cannot drift from the condition.
@Suite("PDF open verdict")
struct PDFOpenOutcomeTests {
    @Test("A document with pages is readable, and says how many")
    func readable() {
        let outcome = PDFOpenOutcome.verdict(pageCount: 12)
        #expect(outcome == .readable(pageCount: 12))
        #expect(outcome.message == nil)
    }

    @Test("A single page is readable, not treated as empty")
    func onePage() {
        // The off-by-one that would show "no pages" for a one-page document.
        #expect(PDFOpenOutcome.verdict(pageCount: 1) == .readable(pageCount: 1))
        #expect(PDFOpenOutcome.verdict(pageCount: 1).message == nil)
    }

    @Test("No document at all means the bytes were not a PDF")
    func notAPDF() {
        let outcome = PDFOpenOutcome.verdict(pageCount: nil)
        #expect(outcome == .notAPDF)
        #expect(outcome.message == "The file is not a readable PDF.")
    }

    @Test("A document with no pages is its own failure, not the same one")
    func noPages() {
        let outcome = PDFOpenOutcome.verdict(pageCount: 0)
        #expect(outcome == .noPages)
        #expect(outcome.message == "The PDF has no pages.")
    }

    @Test("Every failure has a message, and the readable case has none")
    func messagesExistWhereTheyShould() {
        // A failure with no message would leave the viewer showing a spinner forever.
        for count in [nil, 0] as [Int?] {
            #expect(PDFOpenOutcome.verdict(pageCount: count).message != nil)
        }
        // And a message on a readable document would replace the page with an error.
        #expect(PDFOpenOutcome.verdict(pageCount: 3).message == nil)
    }

    @Test("A negative page count is not treated as readable")
    func negative() {
        // PDFKit does not report this, but the guard is a comparison, not an equality, and that
        // is worth pinning: `pageCount != 0` would pass a negative through.
        #expect(PDFOpenOutcome.verdict(pageCount: -1) == .noPages)
    }
}
