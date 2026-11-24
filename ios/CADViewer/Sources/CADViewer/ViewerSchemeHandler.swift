import Foundation
import WebKit
import os
import WebKit
import os

/// Serves the bundled web viewer over a private scheme.
///
/// The viewer needs `fetch`, workers and `WebAssembly.instantiateStreaming`, and all three
/// are restricted under `file://`. A `WKURLSchemeHandler` gives the page a real origin, so
/// the wasm and worker files load as they would from a server, while everything still
/// comes out of the app bundle.
final class ViewerSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cadviewer"

    private let root: URL
    /// The DWG the page should open, set before the page loads.
    private var drawing: Data?
    private var drawingName: String
    private let lock = NSLock()

    init(root: URL, drawing: Data?, drawingName: String) {
        self.root = root
        self.drawing = drawing
        self.drawingName = drawingName
        super.init()
    }

    /// Swaps the drawing without reloading the page, so opening a second DWG keeps the
    /// parsed engine warm.
    func setDrawing(_ data: Data, name: String) {
        lock.lock()
        drawing = data
        drawingName = name
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        // The viewer fetches this to get the bytes it is meant to draw.
        if url.path.hasSuffix("/__dwg__") {
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

        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        // Refuse anything that escapes the bundle, since the path comes from the page.
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let file = root.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path) else {
            respond(task, status: 403, mime: "text/plain", body: Data("forbidden".utf8))
            return
        }
        guard let body = try? Data(contentsOf: file) else {
            respond(task, status: 404, mime: "text/plain", body: Data("not found".utf8))
            return
        }
        respond(task, status: 200, mime: Self.mimeType(for: file.pathExtension), body: body)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Every response is produced synchronously, so there is nothing in flight to cancel.
    }

    private func respond(
        _ task: WKURLSchemeTask, status: Int, mime: String, body: Data
    ) {
        guard let url = task.request.url else { return }
        let headers = [
            "Content-Type": mime,
            "Content-Length": String(body.count),
            "Cache-Control": "no-store",
            // The wasm build of LibreDWG needs these to run at full speed.
            "Cross-Origin-Opener-Policy": "same-origin",
            "Cross-Origin-Embedder-Policy": "require-corp"
        ]
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

    /// WebKit needs the MIME type right: `application/wasm` for streaming instantiation,
    /// and a JavaScript type or the worker is refused.
    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "wasm": return "application/wasm"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }
}
