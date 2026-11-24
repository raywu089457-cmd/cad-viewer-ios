import Foundation

/// The rules for serving the bundled viewer over a custom URL scheme.
///
/// Pulled out of the `WKURLSchemeHandler` so it can be tested without WebKit. Two of these
/// rules are the kind that fail quietly: a wrong MIME type makes WebKit refuse to
/// stream-compile the wasm (the page then shows nothing, with one console warning), and a
/// path that escapes the bundle is a security hole rather than a bug.
public enum BundleServing {
    /// The path the viewer fetches to get the drawing it is meant to draw.
    public static let drawingPath = "/__dwg__"

    /// Whether a request is for the drawing bytes rather than a bundled file.
    public static func isDrawingRequest(path: String) -> Bool {
        path.hasSuffix(drawingPath)
    }

    /// The bundle-relative file a request asks for.
    ///
    /// - Returns: `nil` when the path would escape `root`, which is what a `..` in a URL
    ///   from the page would try. Comparing standardised *components* rather than string
    ///   prefixes matters: `/bundle-evil/x` has `/bundle` as a prefix and is a different
    ///   directory.
    public static func relativeFile(for path: String, root: URL) -> URL? {
        // A URL with an empty path means the site root.
        let requested = path.isEmpty || path == "/" ? "/index.html" : path
        let trimmed = requested.hasPrefix("/") ? String(requested.dropFirst()) : requested

        let rootPath = root.standardizedFileURL.path
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        let candidatePath = candidate.path

        // The candidate must be the root itself or something below it, by path components.
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    /// The MIME type WebKit needs for a file.
    ///
    /// `application/wasm` is not negotiable: `WebAssembly.instantiateStreaming` rejects
    /// anything else, and the LibreDWG engine will not start. JavaScript needs a JS type or
    /// the worker is refused.
    public static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
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

    /// The headers every response carries.
    ///
    /// The cross-origin pair is what lets the wasm engine use shared memory; without them
    /// WebKit may refuse to instantiate it in a worker.
    public static func headers(mime: String, byteCount: Int) -> [String: String] {
        [
            "Content-Type": mime,
            "Content-Length": String(byteCount),
            "Cache-Control": "no-store",
            "Cross-Origin-Opener-Policy": "same-origin",
            "Cross-Origin-Embedder-Policy": "require-corp"
        ]
    }
}
