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
    ///
    /// Compared exactly, not by suffix. `hasSuffix` answered yes for `/evil/__dwg__` and
    /// `/a/b/__dwg__`, which are paths the page never asks for: if one ever arrives it is a bug
    /// or a probe, and answering it with the drawing bytes hides that. The page fetches
    /// `./__dwg__` from its own root, so `/__dwg__` is the only path meant to reach this.
    public static func isDrawingRequest(path: String) -> Bool {
        path == drawingPath
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
        // The bundle ships its dependency licences beside the code, and a type they do not have
        // makes WebKit download them instead of showing them. It is how a reader finds out what
        // the engine underneath is, so it should open.
        case "txt", "md": return "text/plain; charset=utf-8"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }

    /// The headers every response carries.
    ///
    /// The cross-origin pair is what lets the wasm engine use shared memory; without them
    /// WebKit may refuse to instantiate it in a worker.
    ///
    /// `no-store` is deliberate, and it costs a reload of the seventeen-megabyte engine each time
    /// the page comes back. The bundle is a fixed set of files served from the app itself, so
    /// there is nothing to gain from caching it between launches and something to lose while
    /// developing: a rebuilt viewer would keep showing the previous one, with no way to tell.
    /// The engine is warm across drawings within one launch either way — that is the reuse that
    /// matters, and it is `DrawingHandoff`'s job, not the cache's.
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
