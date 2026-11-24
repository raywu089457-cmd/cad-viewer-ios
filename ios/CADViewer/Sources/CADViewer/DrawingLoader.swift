import Foundation
import SwiftDXF
import DXFGeometry

// DrawingKind and LoadFailure come from DXFGeometry: the routing decision and the failure
// messages are plain data with no Apple types in them, so they are unit-tested on machines
// this app cannot be built on.

/// A drawing that has been flattened, ready to draw.
struct LoadedDrawing {
    var name: String
    var scene: DrawScene
    var viewport: Viewport
    /// Wall-clock parse + flatten time, shown so the cost of a big drawing is visible.
    var duration: TimeInterval
    var skipped: [String: Int]
}

/// Reads a drawing off the main thread.
///
/// Parsing a large DXF takes long enough to drop frames, so the caller awaits this from a
/// `Task` and SwiftUI updates when it reports back.
enum DrawingLoader {
    /// Reads and flattens a DXF.
    ///
    /// - Parameters:
    ///   - url: A file the app has access to; security-scoped URLs are opened here.
    ///   - onDarkBackground: Whether ACI 7 should render white.
    static func load(
        url: URL,
        onDarkBackground: Bool = true
    ) async -> Result<LoadedDrawing, LoadFailure> {
        let name = url.lastPathComponent
        let kind = DrawingKind(fileName: name)
        guard kind.canRender else {
            return .failure(
                LoadFailure(
                    fileName: name,
                    reason: .unsupportedType(kind.fileExtension)))
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

        // SwiftDXF reads ASCII DXF only; a binary DXF needs a clear message, not a parse
        // error from deep inside the reader.
        if DXF.isBinary(data) {
            return .failure(LoadFailure(fileName: name, reason: .binaryDXF))
        }

        let started = Date()
        // The options the app opens with, shared with the tests so both exercise the same
        // configuration: expanding blocks, skipping paper space and expanding attributes all
        // change what appears on screen.
        let options = DrawingReadOptions.app
        let drawing: DXF.Drawing
        do {
            drawing = try DXF.read(data: data, options: options)
        } catch {
            return .failure(
                LoadFailure(
                    fileName: name, reason: .unreadable(errorMessage(for: error))))
        }

        let scene = SceneBuilder().build(drawing, onDarkBackground: onDarkBackground)

        guard
            let viewport = Viewport.fit(
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

    /// Turns a parse error into something a reader can act on.
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
