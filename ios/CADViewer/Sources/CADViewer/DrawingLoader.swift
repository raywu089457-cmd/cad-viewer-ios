import SwiftUI
import SwiftDXF
import DXFGeometry

/// Which engine renders a given file.
///
/// DXF is parsed and drawn natively, because SwiftDXF is pure Swift and its geometry
/// becomes a SwiftUI canvas directly. DWG has no open native parser, so it goes to the
/// bundled web viewer running the LibreDWG wasm build inside a `WKWebView`.
enum DrawingKind: Equatable {
    case dxf
    case dwg
    case unsupported(extension: String)

    init(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "dxf": self = .dxf
        case "dwg": self = .dwg
        case let ext: self = .unsupported(extension: ext)
        }
    }

    var canRender: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

/// A drawing that has been flattened, ready to draw.
struct LoadedDrawing {
    var name: String
    var scene: DrawScene
    var viewport: Viewport
    /// Wall-clock parse + flatten time, shown so the cost of a big drawing is visible.
    var duration: TimeInterval
    var skipped: [String: Int]
}

/// Why a drawing could not be shown.
struct LoadFailure: Error, Identifiable {
    enum Reason {
        case unsupportedType(String)
        case unreadable(String)
        case empty
        /// A DXF that is really a binary DXF, which SwiftDXF does not read.
        case binaryDXF
        /// The file is fine but has no model-space geometry to show.
        case noGeometry
    }

    let id = UUID()
    var fileName: String
    var reason: Reason

    var message: String {
        switch reason {
        case .unsupportedType(let ext):
            return ext.isEmpty
                ? "This file has no extension, so its type is unknown."
                : ".\(ext) files cannot be shown here."
        case .unreadable(let detail):
            return detail
        case .empty:
            return "The file is empty."
        case .binaryDXF:
            return "This is a binary DXF. Save it as ASCII DXF to open it here."
        case .noGeometry:
            return "The file parsed, but it holds no model-space geometry."
        }
    }
}

/// Reads a drawing off the main thread.
///
/// Parsing a large DXF takes long enough to drop frames, so it runs detached and reports
/// back on the main actor.
enum DrawingLoader {
    /// Reads and flattens a drawing.
    ///
    /// - Parameters:
    ///   - url: A file the app has access to; security-scoped URLs are opened here.
    ///   - onDarkBackground: Whether ACI 7 should render white.
    static func load(url: URL, onDarkBackground: Bool = true) async -> Result<LoadedDrawing, LoadFailure> {
        let name = url.lastPathComponent
        let kind = DrawingKind(fileName: name)

        guard kind.canRender else {
            if case let .unsupported(ext) = kind {
                return .failure(
                    LoadFailure(fileName: name, reason: .unsupportedType(ext)))
            }
            return .failure(LoadFailure(fileName: name, reason: .unsupportedType("")))
        }

        // A file from the document picker lives outside the sandbox until this is called.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(
                LoadFailure(
                    fileName: name,
                    reason: .unreadable(error.localizedDescription)))
        }
        guard !data.isEmpty else {
            return .failure(LoadFailure(fileName: name, reason: .empty))
        }

        // SwiftDXF reads ASCII DXF only; a binary DXF needs a clear message, not a parse error.
        if DXF.isBinary(data) {
            return .failure(LoadFailure(fileName: name, reason: .binaryDXF))
        }

        let started = Date()
        // Paper space is skipped: a phone screen showing a title block scaled to a whole
        // sheet is not what "open this drawing" means.
        var options = DXF.ReadOptions()
        options.expandBlocks = true
        options.skipPaperSpace = true

        let drawing: DXF.Drawing
        do {
            // `read(data:)` handles the code-page decode and the binary-DXF check itself.
            drawing = try DXF.read(data: data, options: options)
        } catch {
            let detail = errorMessage(for: error)
            return .failure(
                LoadFailure(fileName: name, reason: .unreadable(detail)))
        }

        let scene = SceneBuilder().build(
            drawing, onDarkBackground: onDarkBackground)

        guard let viewport = Viewport.fit(
            points: scene.samplePoints, fallback: scene.bounds)
        else {
            return .failure(LoadFailure(fileName: name, reason: .noGeometry))
        }

        return .success(
            LoadedDrawing(
                name: name,
                scene: scene,
                viewport: viewport,
                duration: Date().timeIntervalSince(started),
                skipped: drawing.skipped
            )
        )
    }

    /// Turns a parse error into something a user can act on.
    private static func errorMessage(for error: Error) -> String {
        guard let dxfError = error as? DXF.Error else {
            return error.localizedDescription
        }
        switch dxfError {
        case .empty:
            return "The file is empty."
        case .binaryUnsupported:
            return "This is a binary DXF. Save it as ASCII DXF to open it here."
        case .notDXF:
            return "This does not look like a DXF drawing."
        }
    }
}
