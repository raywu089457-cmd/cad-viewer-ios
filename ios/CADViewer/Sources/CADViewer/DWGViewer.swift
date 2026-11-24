import SwiftUI
import WebKit
import os

/// The DWG surface: the bundled web viewer in a `WKWebView`.
///
/// DWG has no open native parser, so this is the LibreDWG wasm build running the same
/// viewer that was verified in a browser. The native side only supplies the bytes and
/// relays progress, which keeps the Swift code free of format knowledge.
struct DWGViewer: View {
    var url: URL
    var fileName: String

    @State private var model = DWGViewerModel()
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.07, green: 0.09, blue: 0.11, opacity: 1)

            if let loadError {
                ContentUnavailableView {
                    Label("Could not open the drawing", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
            } else if let webView = model.webView {
                WebViewHost(webView: webView)
            }

            if let status = model.statusText, loadError == nil {
                ProgressView(status)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Reading the file and creating the web view both touch UIKit-adjacent state, so
            // they run on the main actor.
            await model.open(url: url, fileName: fileName) { message in
                loadError = message
            }
        }
    }
}

/// Owns the `WKWebView` and the messages it sends back.
@Observable
final class DWGViewerModel {
    /// Text for the loading overlay, `nil` once the drawing is on screen.
    var statusText: String? = "Preparing the DWG engine…"
    /// The web view, once created. The SwiftUI host inserts it into its hierarchy.
    var webView: WKWebView?

    @ObservationIgnored private var schemeHandler: ViewerSchemeHandler?
    @ObservationIgnored private var readyContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var didBecomeReady = false
    /// Tracks which load is live, so a timeout from an earlier one cannot touch a later
    /// one. The rule is in , which is unit-tested.
    @ObservationIgnored private var loadGeneration = LoadGeneration()
    @ObservationIgnored private var errorHandler: ((String) -> Void)?

    private static let log = Logger(subsystem: "CADViewer", category: "DWGViewer")

    /// Loads the viewer once and hands it the drawing.
    @MainActor
    func open(url: URL, fileName: String, onError: @escaping (String) -> Void) async {
        errorHandler = onError

        // SwiftPM copies the folder into the bundle, but the name it carries depends on how
        // the target is built. Every plausible location is tried, and failing to find one is
        // reported, rather than leaving a blank tab.
        guard let resourceRoot = Bundle.main.resourceURL?.path,
              let viewerPath = ResourceLocation.find(
                path: "Resources/dwgviewer",
                in: resourceRoot,
                exists: { FileManager.default.fileExists(atPath: $0) }),
              FileManager.default.fileExists(atPath: viewerPath + "/index.html")
        else {
            Self.log.error("the dwgviewer folder is missing from the app bundle")
            fail("The DWG viewer was not bundled with the app. Run ios/web/build-for-ios.sh and rebuild.")
            return
        }
        let viewerRoot = URL(fileURLWithPath: viewerPath)

        // The bytes are read here rather than by the page: the page has no file access, and
        // a security-scoped URL from the picker would not survive the handoff.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            fail(error.localizedDescription)
            return
        }

        // A second open reuses the loaded page: the wasm engine stays warm, which is the
        // difference between instant and a three-second reload.
        if didBecomeReady, let webView {
            // The entry point is checked for, not called optimistically. An earlier version
            // wrote `window.cadOpenDwg?.(...)` inside `try?`, so when the page did not define
            // that function the call did nothing at all: no error, no event, no second
            // drawing. If the page cannot take the drawing, reloading it is the honest
            // fallback.
            let handlesDrawing = (try? await webView.evaluateJavaScript(
                "typeof window.cadOpenDwg === 'function'")) as? Bool ?? false
            // A drawing is handed over as base64 inside a JavaScript string, which is both
            // memory and a WebKit call limit. Real DWG files are routinely tens of megabytes,
            // which becomes roughly 4/3 of that as base64 in one string. Past a sensible
            // size, reloading and letting the page fetch from the scheme handler is both
            // faster and the only version that reliably works.
            let handoff = DrawingHandoff(
                byteCount: data.count, pageCanAcceptDirectly: handlesDrawing)
            if handoff == .directly {
                let base64 = data.base64EncodedString()
                // A file name may hold a quote, which would end the JavaScript string.
                let escaped = fileName.replacingOccurrences(
                    of: "'", with: "\\'")
                let script = "window.cadOpenDwg('\(base64)', '\(escaped)', 100)"
                do {
                    _ = try await webView.evaluateJavaScript(script)
                    return
                } catch {
                    Self.log.error("reopening on the loaded page failed; reloading")
                    // Fall through: a reload always works.
                }
            } else if handlesDrawing {
                Self.log.info(
                    "drawing is \(data.count) bytes; reloading to hand it over via the scheme handler")
            } else {
                Self.log.error("the viewer page has no cadOpenDwg entry point; reloading")
            }
            didBecomeReady = false
        }

        // A configuration is copied when the web view is made, so these can only be set up
        // once. A reload reuses them and pushes the new drawing into the existing handler.
        let webView: WKWebView

        if let existingHandler = schemeHandler, let existingWebView = webView {
            // Reloading: the handler is already installed and cannot be replaced.
            existingHandler.setDrawing(data)
            webView = existingWebView
        } else {
            let handler = ViewerSchemeHandler(root: viewerRoot, drawing: data)
            schemeHandler = handler
            let configuration = WKWebViewConfiguration()
            configuration.setURLSchemeHandler(
                handler, forURLScheme: ViewerSchemeHandler.scheme)
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.userContentController.add(self, name: "cadEvents")
            webView = WKWebView(frame: .zero, configuration: configuration)
        }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Pan and pinch belong to the viewer's own canvas; the page must not rubber-band.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        var components = URLComponents()
        components.scheme = ViewerSchemeHandler.scheme
        components.host = "viewer"
        components.path = "/index.html"
        components.queryItems = [URLQueryItem(name: "name", value: fileName)]
        guard let pageURL = components.url else {
            fail("Could not build the viewer URL.")
            return
        }

        // Wait for the page to report ready, so the overlay tracks the engine rather than
        // the web view's load event.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // A load that is still waiting is superseded by this one. Resuming it first
            // matters: a continuation that is never resumed leaks the awaiting task, so the
            // first open would hang forever when the user picks a second file quickly.
            if let superseded = readyContinuation {
                readyContinuation = nil
                superseded.resume()
            }
            let generation = loadGeneration.begin()
            readyContinuation = continuation
            webView.load(URLRequest(url: pageURL))

            Task { @MainActor in
                // Never leave the user staring at a spinner if the engine stays silent.
                try? await Task.sleep(for: .seconds(45))
                // A newer load has taken over; this timeout belongs to a load that is gone.
                guard self.loadGeneration.isCurrent(generation) else { return }
                if let pending = self.readyContinuation {
                    self.readyContinuation = nil
                    pending.resume()
                    Self.log.error("viewer did not report ready")
                    self.fail("The DWG engine did not start.")
                }
            }
        }
    }

    private func fail(_ message: String) {
        statusText = nil
        errorHandler?(message)
    }

    /// Applies an event posted by the page.
    fileprivate func handle(message: [String: Any]) {
        apply(ViewerEvent(message: message))
    }

    /// Applies an already-decoded event.
    ///
    /// The decoding and the state rules live in `ViewerEvent`, which is unit-tested; this
    /// only performs the effects.
    fileprivate func apply(_ event: ViewerEvent) {
        if let text = event.statusText { statusText = text }
        if event.engineIsWarm { didBecomeReady = true }
        if let message = event.errorMessage {
            Self.log.error("viewer error: \(message, privacy: .public)")
            fail(message)
        }
        if event == .ready, let pending = readyContinuation {
            readyContinuation = nil
            pending.resume()
        }
    }
}

extension DWGViewerModel: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        Self.log.error("navigation failed: \(error.localizedDescription, privacy: .public)")
        fail(error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Self.log.error(
            "provisional load failed: \(error.localizedDescription, privacy: .public)")
        fail(error.localizedDescription)
    }
}

extension DWGViewerModel: WKUIDelegate {
    /// Nothing on the page should open a window, but a stray `target=_blank` should not
    /// silently do nothing either.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

extension DWGViewerModel: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        handle(message: body)
    }
}

/// Puts a ready-made `WKWebView` into SwiftUI.
private struct WebViewHost: UIViewRepresentable {
    var webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        // The web view is created once per model; re-add it only if SwiftUI rebuilt the
        // container around it.
        if webView.superview !== container {
            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(webView)
        }
    }
}
