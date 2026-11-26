import Foundation
import SwiftDXF
import DXFGeometry

// DrawingKind and LoadFailure come from DXFGeometry: the routing decision and the failure
// messages are plain data with no Apple types in them, so they are unit-tested on machines
// this app cannot be built on.

/// A drawing that has been flattened, ready to draw.
struct LoadedDrawing {
    var name: String
    /// Where it came from.
    ///
    /// The viewers are identified by this rather than by name, because two files in different
    /// folders can share a name — `drawings/plan.dwg` and `archive/plan.dwg` — and an identity
    /// that collides leaves the previous drawing on screen when the second one is opened.
    /// `URL.standardizedFileURL` so the same file reached two ways is still one file.
    var source: URL
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
    ///
    /// `nonisolated` because the work is CPU-bound parsing, not UI. Without it the body
    /// inherits the caller's actor — which is the main actor, since this is called from a
    /// SwiftUI view — and flattening a large drawing would freeze the interface it is meant
    /// to be loading for.
    nonisolated static func load(
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
            // A Cocoa error description is written for a developer. The reader tapped a file
            // and wants to know what to do next, so the common cases get their own sentence.
            return .failure(
                LoadFailure(
                    fileName: name,
                    reason: .cannotRead(FileReadFailure.classify(error))))
        }
        guard !data.isEmpty else {
            return .failure(LoadFailure(fileName: name, reason: .empty))
        }

        // SwiftDXF reads ASCII DXF only; a binary DXF needs a clear message, not a parse
        // error from deep inside the reader.
        if DXF.isBinary(data) {
            return .failure(LoadFailure(fileName: name, reason: .binaryDXF))
        }

        // A UTF-8 BOM is three bytes before the first group code, and the reader expects a
        // group code there. Without this the whole file reads as zero entities: no error, no
        // geometry, a blank canvas. Windows editors add a BOM by default, so a drawing saved
        // there and mailed on is exactly the file this would refuse to draw.
        let payload = DXFByteOrderMark.stripping(from: data)

        let started = Date()
        // The options the app opens with, shared with the tests so both exercise the same
        // configuration: expanding blocks, skipping paper space and expanding attributes all
        // change what appears on screen.
        let options = DrawingReadOptions.app
        let drawing: DXF.Drawing
        do {
            drawing = try DXF.read(data: payload, options: options)
        } catch {
            return .failure(
                LoadFailure(
                    fileName: name, reason: .unreadable(errorMessage(for: error))))
        }

        let scene = SceneBuilder().build(drawing, onDarkBackground: onDarkBackground)

        // A file that parses but yields nothing drawable. A truncated DXF is the usual cause:
        // its header survives, so the extents are present and a viewport can be framed around
        // them, and the app would then show a blank canvas and call it a success. Saying so is
        // better than an empty screen the reader cannot explain.
        guard
            LoadReadiness.verdict(
                samplePoints: scene.samplePoints, hasBounds: scene.bounds != nil) == .drawable
        else {
            // Nothing to draw can mean two different things, and they need different answers:
            // a thin file, or a file whose layers are all switched off. The second one the
            // reader can fix, so name the layers.
            if !scene.hiddenByLayer.isEmpty {
                return .failure(
                    LoadFailure(
                        fileName: name,
                        reason: .allLayersSwitchedOff(Array(scene.hiddenByLayer.keys))))
            }
            return .failure(LoadFailure(fileName: name, reason: .noGeometry))
        }

        guard
            let viewport = Viewport.fit(
                points: scene.samplePoints, fallback: scene.bounds)
        else {
            return .failure(LoadFailure(fileName: name, reason: .noGeometry))
        }

        return .success(
            LoadedDrawing(
                name: name,
                source: url.standardizedFileURL,
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
