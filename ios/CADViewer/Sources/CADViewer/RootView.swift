import SwiftUI
import UniformTypeIdentifiers
import DXFGeometry

/// The app's only screen: pick a drawing, then route it to the engine that can draw it.
struct RootView: View {
    @State private var loaded: LoadedDrawing?
    @State private var dwg: (url: URL, name: String)?
    @State private var failure: LoadFailure?
    @State private var isLoading = false
    @State private var isPickingFile = false
    /// Shown when the app is launched by opening a file in Files or another app.
    @State private var pendingImport: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let loaded {
                    DXFViewer(drawing: loaded)
                } else if let dwg {
                    DWGViewer(url: dwg.url, fileName: dwg.name)
                } else {
                    welcome
                }
            }
            .toolbar {
                if loaded != nil || dwg != nil {
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
                failure = LoadFailure(
                    fileName: "", reason: .unreadable(error.localizedDescription))
            }
        }
        .onOpenURL { open($0) }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.fileName.isEmpty
                    ? "Could not open the drawing"
                    : "Could not open \(failure.fileName)"),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    /// DXF and DWG only. The two are different engines, and offering more types would
    /// promise more than the app can draw.
    private static let allowedTypes: [UTType] = {
        var types: [UTType] = []
        if let dxf = UTType(filenameExtension: "dxf") { types.append(dxf) }
        if let dwg = UTType(filenameExtension: "dwg") { types.append(dwg) }
        return types.isEmpty ? [.data] : types
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

                Text("Open a DXF or DWG drawing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("**DXF** is drawn natively, with pinch, pan and fit.")
                    } icon: {
                        Image(systemName: "bolt.horizontal")
                            .foregroundStyle(.tint)
                    }
                    Label {
                        Text("**DWG** uses a bundled engine, so it takes a moment to start.")
                    } icon: {
                        Image(systemName: "network")
                            .foregroundStyle(.tint)
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
                Label("Open a drawing", systemImage: "folder")
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

    /// Routes a file to the native reader or the web viewer.
    private func open(_ url: URL) {
        reset()
        let kind = DrawingKind(fileName: url.lastPathComponent)

        switch kind {
        case .dxf:
            Task {
                isLoading = true
                // The parse runs off the main thread; the loader hops back when it is done.
                let result = await DrawingLoader.load(url: url)
                isLoading = false
                switch result {
                case .success(let drawing):
                    loaded = drawing
                case .failure(let error):
                    failure = error
                }
            }

        case .dwg:
            // The web view reads the bytes itself, so the URL is handed over as-is.
            dwg = (url, url.lastPathComponent)

        case .unsupported(let ext):
            failure = LoadFailure(
                fileName: url.lastPathComponent, reason: .unsupportedType(ext))
        }
    }

    private func reset() {
        loaded = nil
        dwg = nil
        failure = nil
    }
}

#Preview {
    RootView()
}
