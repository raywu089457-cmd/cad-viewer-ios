import SwiftUI
import PDFKit
import UIKit

/// The PDF surface.
///
/// `PDFKit`'s own view already does scrolling, pinch-zoom, text selection and links, and it
/// renders through the same PDF engine the system uses, so there is nothing to gain from
/// reimplementing it. This wraps it and adds what a drawing-oriented reader wants: page
/// count, fit-to-width on first open, and fitting the whole page.
struct PDFViewer: View {
    var url: URL
    var fileName: String

    @State private var model = PDFViewerModel()

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.07, green: 0.09, blue: 0.11, opacity: 1)

            if let error = model.error {
                ContentUnavailableView {
                    Label("Could not open the PDF", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if let document = model.document {
                PDFKitView(document: document, autoScales: model.autoScales)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView("Opening…").foregroundStyle(.white)
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.document != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.autoScales.toggle()
                    } label: {
                        Label(
                            model.autoScales ? "Fit whole page" : "Fit width",
                            systemImage: model.autoScales
                                ? "rectangle.compress.vertical"
                                : "rectangle.expand.vertical"
                        )
                    }
                }
            }
        }
        .task { model.open(url: url) }
    }
}

/// The state a PDF view needs, kept out of the view body.
@Observable
final class PDFViewerModel {
    var document: PDFDocument?
    var error: String?
    /// `true` fits the whole page, `false` fits the width, which is how drawings are read.
    var autoScales = true

    func open(url: URL) {
        // A file from the document picker lives outside the sandbox until this is called.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            error = "The file is not a readable PDF."
            return
        }
        guard document.pageCount > 0 else {
            error = "The PDF has no pages."
            return
        }
        self.document = document
    }
}

/// Hosts `PDFView`, which has no SwiftUI equivalent.
private struct PDFKitView: UIViewRepresentable {
    var document: PDFDocument
    /// Whether the page should fit the whole view or just the width.
    var autoScales: Bool

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = autoScales
        view.backgroundColor = UIColor(
            red: 0.07, green: 0.09, blue: 0.11, alpha: 1)
        // A drawing is often wider than the screen; allow pinching out far enough to read
        // small text without the page snapping back.
        view.minScaleFactor = max(view.scaleFactorForSizeToFit / 4, 0.01)
        view.maxScaleFactor = max(view.scaleFactorForSizeToFit * 12, 4)
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if view.autoScales != autoScales {
            view.autoScales = autoScales
            // Re-frame after switching, or the page keeps the previous zoom.
            if let page = view.currentPage {
                view.go(to: page)
            }
            view.scaleFactor = view.scaleFactorForSizeToFit
        }
    }
}
