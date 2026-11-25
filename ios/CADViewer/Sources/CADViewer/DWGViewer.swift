import SwiftUI
import WebKit
import os
import DXFGeometry

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
        .toolbar {
            // Shown only once there is a drawing, because before that there is nothing to frame
            // and a button that does nothing is worse than no button.
            if model.webView != nil, loadError == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.zoomToFit() }
                    } label: {
                        Label("Fit drawing", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
        }
        .task {
            // Reading the file and creating the web view both touch UIKit-adjacent state, so
            // they run on the main actor.
            await model.open(url: url, fileName: fileName) { message in
                loadError = message
            }
        }
        .onDisappear {
            // Closing the drawing has to free the page: it holds the wasm engine, which is
            // tens of megabytes, and a viewer that leaks one per open is a viewer that runs
            // out of memory after a few files.
            model.tearDown()
        }
    }
}

/// Owns the `WKWebView` and the messages it sends back.
/// The state a DWG view needs.
///
/// `@MainActor` because it is UI state and `@Observable` does not provide isolation by
/// itself: WebKit delivers script messages and navigation callbacks without promising a
/// thread, so without this the view's state could be written off the main thread — a data
/// race the compiler would not have caught before Swift 6, and one that shows up as a
/// corrupted or stale interface rather than a crash.
@Observable
@MainActor
final class DWGViewerModel {
    /// Text for the loading overlay, `nil` once the drawing is on screen.
    var statusText: String? = "Preparing the DWG engine…"
    /// The web view, once created. The SwiftUI host inserts it into its hierarchy.
    var webView: WKWebView?

    @ObservationIgnored private var schemeHandler: ViewerSchemeHandler?
    /// The weak proxy registered with the page, held so it is not collected while the page
    /// still refers to it. The proxy holds the model weakly, which is what breaks the cycle.
    @ObservationIgnored private var messageHandlerProxy: WeakScriptMessageHandler?
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
        //
        // Read off the main actor. This method is @MainActor because it drives the view, but a
        // real DWG is routinely tens of megabytes and reading one on the main thread freezes
        // the interface for the whole read — while the spinner that says "loading" is
        // itself unable to update.
        let data: Data
        do {
            data = try await Self.readBytes(at: url)
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
        //
        // Named `page`, not `webView`: a local of that name shadows `self.webView`, and the
        // optional binding below then reads the local rather than the model's — which is never
        // nil, so the reload path could not be taken.
        let page: WKWebView

        if let existingHandler = schemeHandler, let existingWebView = webView {
            // Reloading: the handler is already installed and cannot be replaced.
            existingHandler.setDrawing(data)
            page = existingWebView
        } else {
            let handler = ViewerSchemeHandler(root: viewerRoot, drawing: data)
            schemeHandler = handler
            let configuration = WKWebViewConfiguration()
            configuration.setURLSchemeHandler(
                handler, forURLScheme: ViewerSchemeHandler.scheme)
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            // A weak proxy rather than `self`. A user content controller holds its handlers
            // strongly, and the model holds the web view, so registering the model directly
            // makes the two keep each other alive: dismissing the viewer would leak the page
            // and its wasm engine, tens of megabytes per drawing opened.
            let proxy = WeakScriptMessageHandler(target: self)
            messageHandlerProxy = proxy
            configuration.userContentController.add(proxy, name: "cadEvents")
            page = WKWebView(frame: .zero, configuration: configuration)
        }
        page.isOpaque = false
        page.backgroundColor = .clear
        page.scrollView.backgroundColor = .clear
        // Pan and pinch belong to the viewer's own canvas; the page must not rubber-band.
        page.scrollView.isScrollEnabled = false
        page.scrollView.bounces = false
        page.navigationDelegate = self
        page.uiDelegate = self
        self.webView = page

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
            page.load(URLRequest(url: pageURL))

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

    /// Reads a file's bytes away from the main actor.
    ///
    /// The security-scoped access is opened and closed inside, because the URL is only valid
    /// for as long as the scope is held and the caller no longer controls that lifetime.
    nonisolated static func readBytes(at url: URL) async throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func fail(_ message: String) {
        statusText = nil
        errorHandler?(message)
    }

    /// Frames the whole drawing again.
    ///
    /// The native layer draws no zoom controls for DWG — the page's own canvas handles pinch
    /// and drag — so a reader who pinched past the edge had no way back but reopening the file.
    /// The page exposes the engine's fit call for this; the toolbar button calls it.
    func zoomToFit() async {
        guard let webView else { return }
        do {
            _ = try await webView.evaluateJavaScript("window.cadZoomToFit?.()")
        } catch {
            // A page that cannot run the script is one still loading, or one whose engine
            // failed; in both cases there is nothing framed to return to.
            Self.log.error("zoom to fit failed: \(error.localizedDescription)")
        }
    }

    /// Releases the page and the engine it loaded.
    ///
    /// Called when the viewer goes away. The proxy already breaks the retain cycle, so this
    /// is not what makes it free; it is what makes it free promptly, rather than when the
    /// page happens to be collected after downloading tens of megabytes of wasm.
    func tearDown() {
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: "cadEvents")
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        messageHandlerProxy = nil
        schemeHandler = nil
        // A wait that will never be signalled by a page that is gone.
        if let pending = readyContinuation {
            readyContinuation = nil
            pending.resume()
        }
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
    /// `nonisolated` because the protocol is, then asserted back onto the main actor:
    /// navigation callbacks are delivered on the main thread, and both of these report
    /// through the model's state.
    nonisolated func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        MainActor.assumeIsolated {
            logAndFail("navigation failed", error)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            logAndFail("provisional load failed", error)
        }
    }

    private func logAndFail(_ what: String, _ error: Error) {
        Self.log.error("\(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        fail(error.localizedDescription)
    }
}

extension DWGViewerModel: WKUIDelegate {
    /// Nothing on the page should open a window, but a stray `target=_blank` should not
    /// silently do nothing either.
    ///
    /// `nonisolated` because the protocol is. Nothing here touches the model, so there is
    /// nothing to assert back onto the main actor.
    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

extension DWGViewerModel: WKScriptMessageHandler {
    /// `nonisolated` because the protocol is, then asserted back onto the main actor: WebKit
    /// delivers these on the main thread, and the model's state may only be touched there.
    nonisolated func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            handleMessage(message)
        }
    }

    private func handleMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            // A message the page sent in a shape this does not understand. Dropping it in
            // silence is how a broken page comes to look like a working one: the app would
            // sit on its spinner with nothing in the log to say why.
            Self.log.error(
                "ignoring a message that is not a dictionary: \(String(describing: type(of: message.body)), privacy: .public)")
            return
        }
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

/// Forwards script messages without keeping the target alive.
///
/// `WKUserContentController` holds its handlers strongly. Registering the model itself would
/// make the model and the web view keep each other alive — the model holds the view, the
/// view's configuration holds the model — and dismissing the viewer would leak the page and
/// the wasm engine it had loaded, tens of megabytes for every drawing opened.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // The target is gone: nothing to forward to, and the controller can drop this proxy.
        target?.userContentController(userContentController, didReceive: message)
    }
}
