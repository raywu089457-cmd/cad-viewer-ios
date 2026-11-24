import SwiftUI
import UniformTypeIdentifiers
import DXFGeometry

/// The app's only screen: pick a file, then route it to the engine that can draw it.
struct RootView: View {
    /// State of the file currently on screen, if any.
    private enum Opened: Equatable {
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

    @State private var opened: Opened?
    @State private var failure: LoadFailure?
    @State private var isLoading = false
    @State private var isPickingFile = false

    var body: some View {
        NavigationStack {
            Group {
                switch opened {
                case .dxf(let drawing):
                    DXFViewer(drawing: drawing)
                case .dwg(let url, let name):
                    DWGViewer(url: url, fileName: name)
                case .pdf(let url, let name):
                    PDFViewer(url: url, fileName: name)
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
                failure = LoadFailure(
                    fileName: "", reason: .unreadable(error.localizedDescription))
            }
        }
        // Opening a file from Files, Mail or another app.
        .onOpenURL { open($0) }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(
                    failure.fileName.isEmpty
                        ? "Could not open the file"
                        : "Could not open \(failure.fileName)"),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    /// DXF, DWG and PDF only. Offering more types would promise more than the app can show.
    private static let allowedTypes: [UTType] = {
        var types: [UTType] = [.pdf]
        if let dxf = UTType(filenameExtension: "dxf") { types.append(dxf) }
        if let dwg = UTType(filenameExtension: "dwg") { types.append(dwg) }
        return types
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
        let name = url.lastPathComponent

        switch DrawingKind(fileName: name) {
        case .dxf:
            Task {
                isLoading = true
                // The parse runs off the main thread; the loader reports back on the main
                // actor when it finishes.
                let result = await DrawingLoader.load(url: url)
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
    }
}

#Preview {
    RootView()
}
