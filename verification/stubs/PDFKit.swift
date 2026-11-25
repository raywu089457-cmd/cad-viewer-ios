// A stub of the PDFKit surface this app uses.
import Foundation
import SwiftUI
import SwiftUI

public final class PDFDocument {
    public var pageCount: Int = 0
    public init?(url: URL) {}
}

public final class PDFPage {
    /// The page box, in points. A drawing is read from the top left of the media box.
    public func bounds(for box: Box) -> CGRect { CGRect() }
    public enum Box { case mediaBox, cropBox, bleedBox, trimBox, artBox }
}

/// Where to scroll to: a page and a point on it.
public final class PDFDestination {
    public init(page: PDFPage, at point: CGPoint) {}
}

public final class PDFView: UIView {
    public var document: PDFDocument?
    public var autoScales: Bool = true
    public var minScaleFactor: Double = 0
    public var maxScaleFactor: Double = 1
    public var scaleFactor: Double = 1
    public var scaleFactorForSizeToFit: Double = 1
    public var displayMode: DisplayMode = .singlePageContinuous
    public var displayDirection: DisplayDirection = .vertical
    /// The grey band PDFKit draws between pages in continuous mode. Default true.
    public var displaysPageBreaks: Bool = true
    public var currentPage: PDFPage? { nil }
    public var currentDestination: PDFDestination? { nil }
    // `init()` and `backgroundColor` are inherited from UIView.
    /// Takes a destination, not a page. The two are different types and everything that
    /// reads "scroll to this page" wants a destination built from one.
    public func go(to destination: PDFDestination) {}

    public enum DisplayMode { case singlePage, singlePageContinuous }
    public enum DisplayDirection { case vertical, horizontal }
}
