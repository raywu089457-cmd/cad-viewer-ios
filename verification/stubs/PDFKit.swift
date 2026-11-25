// A stub of the PDFKit surface this app uses.
import Foundation
import SwiftUI
import SwiftUI

public final class PDFDocument {
    public var pageCount: Int = 0
    public init?(url: URL) {}
}

public final class PDFPage {}

public final class PDFView: UIView {
    public var document: PDFDocument?
    public var autoScales: Bool = true
    public var minScaleFactor: Double = 0
    public var maxScaleFactor: Double = 1
    public var scaleFactor: Double = 1
    public var scaleFactorForSizeToFit: Double = 1
    public var displayMode: DisplayMode = .singlePageContinuous
    public var displayDirection: DisplayDirection = .vertical
    public var currentPage: PDFPage? { nil }
    public init() {}
    public func go(to page: PDFPage) {}

    public enum DisplayMode { case singlePage, singlePageContinuous }
    public enum DisplayDirection { case vertical, horizontal }
}
