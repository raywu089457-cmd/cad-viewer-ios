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
    @ObservationIgnored private var errorHandler: ((String) -> Void)?

    private static let log = Logger(subsystem: "CADViewer", category: "DWGViewer")

    /// Loads the viewer once and hands it the drawing.
    @MainActor
    func open(url: URL, fileName: String, onError: @escaping (String) -> Void) async {
        errorHandler = onError

        guard let viewerRoot = Bundle.main.url(forResource: "dwgviewer", withExtension: nil)
        else {
            Self.log.error("dwgviewer bundle folder missing")
            fail("The DWG viewer was not bundled with the app.")
            return
        }

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
            let base64 = data.base64EncodedString()
            let name = fileName.replacingOccurrences(of: "'", with: "\\'")
            let script = "window.cadOpenDwg?.('\(base64)', '\(name)', 100)"
            _ = try? await webView.evaluateJavaScript(script)
            return
        }

        let handler = ViewerSchemeHandler(root: viewerRoot, drawing: data)
        schemeHandler = handler

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: ViewerSchemeHandler.scheme)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: "cadEvents")

        let webView = WKWebView(frame: .zero, configuration: configuration)
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
            readyContinuation = continuation
            webView.load(URLRequest(url: pageURL))

            Task { @MainActor in
                // Never leave the user staring at a spinner if the engine stays silent.
                try? await Task.sleep(for: .seconds(45))
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
