import SwiftUI
import UniformTypeIdentifiers
import DXFGeometry

/// The app's only screen: pick a file, then route it to the engine that can draw it.
struct RootView: View {
    /// State of the file currently on screen, if any.
    ///
    /// Not `Equatable`: the DXF case carries a `LoadedDrawing`, which holds a whole
    /// flattened scene. Comparing those to decide whether the view changed would walk
    /// thousands of points on every SwiftUI update, for no benefit — the `switch` below
    /// only needs destructuring.
    private enum Opened {
        case dxf(LoadedDrawing)
        case dwg(url: URL, name: String)
        case pdf(url: URL, name: String)

        var name: String {
            switch self {
            case .dxf(let drawing): return drawing.name
            case .dwg(_, let name), .pdf(_, let name): return name
            }
        }
    }

    /// What a viewer is rebuilt in response to.
    ///
    /// The file alone was not enough: reopening the same file left the `.id()` unchanged, and
    /// SwiftUI kept the viewer with its loaded page. For DWG and PDF the reset and the reopen
    /// happen in one run loop tick, so the intermediate `nil` never renders and nothing forces a
    /// rebuild — a drawing edited on disk and reopened showed the version from before the edit.
    ///
    /// The counter is part of the identity so every open produces a new one.
    private struct ViewerID: Hashable {
        var file: URL
        var open: Int
    }

    @State private var opened: Opened?
    @State private var failure: LoadFailure?
    @State private var isLoading = false
    /// Which load is live.
    ///
    /// Opening a second file while the first is still parsing would otherwise let the
    /// abandoned one land later and replace the file the reader actually chose.
    @State private var loadGeneration = LoadGeneration()
    @State private var isPickingFile = false
    /// Bumped on every open, and part of each viewer's identity.
    ///
    /// The identity is the file, so a viewer is not rebuilt when a different file is opened — but
    /// that also meant it was not rebuilt when the *same* file was opened again. A drawing edited
    /// and saved externally, then reopened here, showed the version from before the edit: the
    /// `.id()` was unchanged and SwiftUI kept the viewer, with its `@State` model and its loaded
    /// page. `reset()` sets `opened` to nil and back within one run loop tick for DWG and PDF, so
    /// SwiftUI never renders the intermediate state that would have forced a rebuild.
    @State private var openCount = 0

    var body: some View {
        NavigationStack {
            Group {
                switch opened {
                case .dxf(let drawing):
                    // Identifying the viewer by file forces SwiftUI to build a new one when a
                    // different drawing is opened. Without it the same view persists and its
                    // `@State` transform keeps the previous drawing's centre and scale: the
                    // second file would open showing the first file's view of the world.
                    DXFViewer(drawing: drawing)
                        .id(ViewerID(file: drawing.source, open: openCount))
                case .dwg(let url, let name):
                    // Identified by file for the same reason as the DXF viewer: its `@State`
                    // model carries the loaded page, and a new drawing on the same instance
                    // would keep the previous one's web view.
                    DWGViewer(url: url, fileName: name)
                        .id(ViewerID(file: url.standardizedFileURL, open: openCount))
                case .pdf(let url, let name):
                    PDFViewer(url: url, fileName: name)
                        .id(ViewerID(file: url.standardizedFileURL, open: openCount))
                case nil:
                    welcome
                }
            }
            .toolbar {
                if opened != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { reset() }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { open(url) }
            case .failure(let error):
                // Dismissing the picker arrives here as a failure. Reporting it as one would
                // show an error for an action that did nothing wrong.
                if FilePickOutcome.isCancellation(error) { return }
                failure = LoadFailure(
                    fileName: "", reason: .unreadable(error.localizedDescription))
            }
        }
        // Opening a file from Files, Mail or another app.
        .onOpenURL { open($0) }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            ),
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    /// DXF, DWG and PDF only. Offering more types would promise more than the app can show.
    private static let allowedTypes: [UTType] = {
        // The identifiers Info.plist declares, used by name rather than derived from the file
        // extension. UTType(filenameExtension:) only answers for a type the system has
        // registered, and returning nil there would silently drop the type from the picker,
        // so a drawing would not be selectable with nothing to say why.
        //
        // A type that is not declared resolves to an empty UTType rather than nil, so a
        // missing declaration fails loudly at the first import instead of quietly narrowing
        // the picker.
        let identifiers = ["com.autodesk.dxf", "com.autodesk.dwg", "com.adobe.pdf"]
        return identifiers.map { UTType($0) ?? .data }
    }()

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)

                Text("CAD Viewer")
                    .font(.title2.weight(.semibold))

                Text("Open a DXF, DWG or PDF file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("**DXF** is drawn natively, with pinch, pan and fit.")
                    } icon: {
                        Image(systemName: "bolt.horizontal").foregroundStyle(.tint)
                    }
                    Label {
                        Text("**DWG** uses a bundled engine, so it takes a moment to start.")
                    } icon: {
                        Image(systemName: "network").foregroundStyle(.tint)
                    }
                    Label {
                        Text("**PDF** opens in the system reader.")
                    } icon: {
                        Image(systemName: "doc.richtext").foregroundStyle(.tint)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300, alignment: .leading)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Spacer()

            Button {
                isPickingFile = true
            } label: {
                Label("Open a file", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .overlay {
            if isLoading {
                ProgressView("Opening…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    /// Routes a file to the engine that can show it.
    private func open(_ url: URL) {
        reset()
        // Part of the viewers' identity, so reopening the same file rebuilds the viewer and
        // re-reads it. See `openCount`.
        openCount += 1
        let name = url.lastPathComponent

        switch DrawingKind(fileName: name) {
        case .dxf:
            let generation = loadGeneration.begin()
            Task {
                isLoading = true
                // `DrawingLoader.load` is nonisolated, so the parse runs on the cooperative
                // pool rather than the main actor this view is on: a large drawing would
                // otherwise freeze the interface while it loaded. The await returns here.
                let result = await DrawingLoader.load(url: url)
                // A file picked while this one was parsing has taken over. Its result is the
                // one the reader asked for; this one is abandoned.
                guard loadGeneration.isCurrent(generation) else { return }
                isLoading = false
                switch result {
                case .success(let drawing):
                    opened = .dxf(drawing)
                case .failure(let error):
                    failure = error
                }
            }

        case .dwg:
            // The web view reads the bytes itself, so the URL is handed over as-is.
            opened = .dwg(url: url, name: name)

        case .pdf:
            // PDFKit also reads the URL itself, and copes with security-scoped access.
            opened = .pdf(url: url, name: name)

        case .unsupported(let ext):
            failure = LoadFailure(
                fileName: name, reason: .unsupportedType(ext))
        }
    }

    private func reset() {
        opened = nil
        failure = nil
        // Any load already in flight belongs to a file the reader has moved on from. Bumping
        // the generation here means its result is discarded rather than drawn over the next
        // one, which `open` calls after this.
        _ = loadGeneration.begin()
    }
}

#Preview {
    RootView()
}
