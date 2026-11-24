import Testing
import Foundation
@testable import DXFGeometry

/// The rules the `WKURLSchemeHandler` follows. Two of these fail quietly if wrong: a bad
/// MIME type stops WebKit instantiating the wasm, and a path that escapes the bundle is a
/// security hole. Neither shows up as an error message.
@Suite("Bundle serving")
struct BundleServingTests {
    let root = URL(fileURLWithPath: "/app/dwgviewer")

    @Test("The drawing endpoint is recognised by suffix")
    func drawingRequest() {
        #expect(BundleServing.isDrawingRequest(path: "/__dwg__"))
        #expect(BundleServing.isDrawingRequest(path: "/anything/__dwg__"))
        #expect(!BundleServing.isDrawingRequest(path: "/index.html"))
        #expect(!BundleServing.isDrawingRequest(path: "/__dwg__/x"))
    }

    @Test("A normal file resolves inside the bundle")
    func normalFile() throws {
        let file = try #require(BundleServing.relativeFile(for: "/index.html", root: root))
        #expect(file.lastPathComponent == "index.html")
        #expect(file.path.hasPrefix("/app/dwgviewer/"))
    }

    @Test("The site root maps to index.html")
    func rootPath() {
        #expect(
            BundleServing.relativeFile(for: "/", root: root)?.lastPathComponent
                == "index.html")
        #expect(
            BundleServing.relativeFile(for: "", root: root)?.lastPathComponent
                == "index.html")
    }

    @Test("A nested file resolves")
    func nestedFile() {
        #expect(
            BundleServing.relativeFile(for: "/assets/app.js", root: root)?
                .path.hasSuffix("assets/app.js") == true)
    }

    @Test("Nothing may escape the bundle")
    func escapes() {
        // The page sends these paths, so they are attacker-controlled.
        #expect(BundleServing.relativeFile(for: "/../secrets.txt", root: root) == nil)
        #expect(BundleServing.relativeFile(for: "/../../etc/passwd", root: root) == nil)
        #expect(BundleServing.relativeFile(for: "/assets/../../secrets", root: root) == nil)
    }

    @Test("A sibling directory sharing a string prefix is not inside the bundle")
    func siblingPrefix() {
        // "/app/dwg" is a string prefix of "/app/dwgviewer" but a different directory, which
        // is exactly what a naive `hasPrefix` comparison gets wrong.
        let shorterRoot = URL(fileURLWithPath: "/app/dwg")
        #expect(
            BundleServing.relativeFile(
                for: "/../dwgviewer/index.html", root: shorterRoot) == nil)
    }

    @Test("Wasm is served as application/wasm")
    func wasmMime() {
        // Not negotiable: instantiateStreaming rejects anything else.
        #expect(BundleServing.mimeType(forExtension: "wasm") == "application/wasm")
    }

    @Test("JavaScript is served as JavaScript, whatever the case")
    func jsMime() {
        #expect(BundleServing.mimeType(forExtension: "js").hasPrefix("text/javascript"))
        #expect(BundleServing.mimeType(forExtension: "JS").hasPrefix("text/javascript"))
        #expect(BundleServing.mimeType(forExtension: "mjs").hasPrefix("text/javascript"))
    }

    @Test("Unknown extensions are octets, not guessed")
    func unknownMime() {
        #expect(
            BundleServing.mimeType(forExtension: "weird") == "application/octet-stream")
    }

    @Test("Headers carry the length and the policy the wasm worker needs")
    func headers() {
        let headers = BundleServing.headers(mime: "application/wasm", byteCount: 1234)
        #expect(headers["Content-Type"] == "application/wasm")
        #expect(headers["Content-Length"] == "1234")
        #expect(headers["Cache-Control"] == "no-store")
        #expect(headers["Cross-Origin-Embedder-Policy"] == "require-corp")
    }
}
