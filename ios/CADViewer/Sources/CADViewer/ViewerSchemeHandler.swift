import Foundation
import WebKit
import os
import DXFGeometry

/// Serves the bundled web viewer over a private scheme.
///
/// The viewer needs `fetch`, workers and `WebAssembly.instantiateStreaming`, and all three
/// are restricted under `file://`. A `WKURLSchemeHandler` gives the page a real origin, so
/// the wasm and worker files load as they would from a server, while everything still
/// comes out of the app bundle.
final class ViewerSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cadviewer"

    private static let log = Logger(
        subsystem: "CADViewer", category: "ViewerSchemeHandler")

    private let root: URL
    /// The DWG the page should open, set before the page loads.
    private var drawing: Data?
    private let lock = NSLock()

    init(root: URL, drawing: Data?) {
        self.root = root
        self.drawing = drawing
        super.init()
    }

    /// Replaces the drawing the page will fetch.
    ///
    /// This is not an optimisation, it is required: a `WKWebViewConfiguration` is copied
    /// when the web view is created, so a handler added afterwards never takes effect. When
    /// a reopen falls back to reloading the page, the handler that is already installed has
    /// to be told about the new drawing or the page fetches the previous one.
    func setDrawing(_ data: Data) {
        lock.lock()
        drawing = data
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        // The viewer fetches this to get the bytes it is meant to draw.
        if BundleServing.isDrawingRequest(path: url.path) {
            lock.lock()
            let payload = drawing
            lock.unlock()
            guard let payload else {
                respond(task, status: 404, mime: "text/plain", body: Data("no drawing".utf8))
                return
            }
            respond(task, status: 200, mime: "application/octet-stream", body: payload)
            return
        }

        // Refuse anything that escapes the bundle: the path comes from the page.
        guard let file = BundleServing.relativeFile(for: url.path, root: root) else {
            respond(task, status: 403, mime: "text/plain", body: Data("forbidden".utf8))
            return
        }
        guard let body = try? Data(contentsOf: file) else {
            // 404 either way, but logged: a file that exists and cannot be read is a different
            // problem from one that is not there, and the browser only sees "not found".
            Self.log.error(
                "cannot read \(file.lastPathComponent, privacy: .public) from the bundle")
            respond(task, status: 404, mime: "text/plain", body: Data("not found".utf8))
            return
        }
        respond(task, status: 200, mime: BundleServing.mimeType(forExtension: file.pathExtension), body: body)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Every response is produced synchronously, so there is nothing in flight to cancel.
    }

    private func respond(
        _ task: WKURLSchemeTask, status: Int, mime: String, body: Data
    ) {
        guard let url = task.request.url else { return }
        let headers = BundleServing.headers(mime: mime, byteCount: body.count)
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: headers)
        else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

}
