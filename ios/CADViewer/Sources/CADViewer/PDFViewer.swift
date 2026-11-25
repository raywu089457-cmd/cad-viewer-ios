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
        .task { await model.open(url: url) }
    }
}

/// The state a PDF view needs, kept out of the view body.
///
/// `@MainActor` because it is UI state: `@Observable` is a change-tracking macro, not an
/// isolation guarantee, and a comment here previously claimed otherwise.
@Observable
@MainActor
final class PDFViewerModel {
    var document: PDFDocument?
    var error: String?
    /// `true` fits the whole page, `false` fits the width, which is how drawings are read.
    var autoScales = true

    func open(url: URL) async {
        // Opening a PDF reads and indexes it. On a large drawing that is long enough to be
        // felt, and this class is main-actor bound, so doing the work here would freeze the
        // interface before the view even appears.
        let outcome = await Self.load(url: url)
        switch outcome {
        case .success(let loaded):
            document = loaded
        case .failure(let reason):
            error = reason
        }
    }

    /// Opens a PDF away from the main actor.
    enum OpenOutcome {
        case success(PDFDocument)
        case failure(String)
    }

    nonisolated static func load(url: URL) async -> OpenOutcome {
        // A file from the document picker lives outside the sandbox until this is called.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            return .failure("The file is not a readable PDF.")
        }
        guard document.pageCount > 0 else {
            return .failure("The PDF has no pages.")
        }
        return .success(document)
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
        // Not measured yet at this point: the view has no size until layout, so the limits
        // are set from the fit scale in updateUIView once it is real. A drawing is often wider
        // than the screen, so the range has to allow pinching out far enough to read small
        // text without the page snapping back.
        let limits = PDFZoom.limits(fitScale: view.scaleFactorForSizeToFit)
        view.minScaleFactor = limits.minimum
        view.maxScaleFactor = limits.maximum
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }

        // Layout has happened by now, so the fit scale is meaningful and the pinch range can
        // be derived from it. Doing this only in makeUIView left the range at its fallback.
        let limits = PDFZoom.limits(fitScale: view.scaleFactorForSizeToFit)
        if limits.measured {
            view.minScaleFactor = limits.minimum
            view.maxScaleFactor = limits.maximum
        }
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
