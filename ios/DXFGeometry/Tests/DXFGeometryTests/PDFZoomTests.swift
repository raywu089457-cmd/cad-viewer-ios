import Testing
@testable import DXFGeometry

/// The pinch limits for a PDF page.
///
/// `scaleFactorForSizeToFit` is only meaningful once the view has a size. Asking for it in
/// `makeUIView` — before layout — yields zero, and limits derived from that were a floor of
/// 0.01 and a ceiling of 4: a pinch range far narrower than a drawing needs, with nothing to
/// say it had gone wrong.
@Suite("PDF zoom limits")
struct PDFZoomTests {
    @Test("An unmeasured view reports itself as unmeasured")
    func unmeasured() {
        #expect(!PDFZoom.limits(fitScale: 0).measured)
        // NaN and negatives are no better than zero.
        #expect(!PDFZoom.limits(fitScale: .nan).measured)
        #expect(!PDFZoom.limits(fitScale: -1).measured)
    }

    @Test("The fallback range is usable")
    func fallback() {
        let limits = PDFZoom.limits(fitScale: 0)
        #expect(limits.maximum > limits.minimum)
    }

    @Test("A real fit scale gives a proportional range")
    func measured() {
        let limits = PDFZoom.limits(fitScale: 2)
        #expect(limits.measured)
        #expect(abs(limits.minimum - 0.5) < 1e-9)
        #expect(abs(limits.maximum - 24) < 1e-9)
    }

    @Test("A larger page zooms further, rather than clamping to a fixed pair")
    func scales() {
        let smaller = PDFZoom.limits(fitScale: 2)
        let bigger = PDFZoom.limits(fitScale: 4)
        #expect(bigger.maximum > smaller.maximum)
        #expect(bigger.minimum > smaller.minimum)
    }
}
