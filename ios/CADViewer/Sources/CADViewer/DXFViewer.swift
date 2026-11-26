import SwiftUI
import DXFGeometry

/// The DXF reading surface: the drawing, its gestures, and the zoom controls.
struct DXFViewer: View {
    var drawing: LoadedDrawing

    @State private var transform: ViewTransform
    /// Each gesture keeps its own origin, in a type that is tested on its own. Both are live at
    /// once, and sharing one origin made the second gesture start from a stale transform the
    /// moment the first ended.
    @State private var pan = GestureSession()
    @State private var pinch = GestureSession()
    @State private var showsDetails = false

    private static let background = Color(
        .sRGB, red: 0.07, green: 0.09, blue: 0.11, opacity: 1)

    init(drawing: LoadedDrawing) {
        self.drawing = drawing
        // A placeholder size; the real size arrives in `onAppear` and is applied then.
        _transform = State(
            initialValue: ViewTransform.fitting(
                drawing.viewport.bounds,
                in: ScreenSize(width: 390, height: 844)))
    }

    var body: some View {
        GeometryReader { proxy in
            DrawingCanvas(
                scene: drawing.scene,
                transform: transform,
                background: Self.background
            )
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2) { fit(to: proxy.size) }
            .onAppear { fit(to: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                transform.resize(to: newSize.screenSize)
            }
            // Belt and braces for the same problem: `RootView` already identifies this view by
            // file name so a new drawing gets a new viewer, but if a caller ever passes a
            // different drawing to the same instance, the framing has to follow it rather
            // than keep the old drawing's centre and scale.
            .onChange(of: drawing.name) { _, _ in
                fit(to: proxy.size)
            }
            .overlay(alignment: .bottomTrailing) { controls }
            .overlay(alignment: .top) { outsideHint }
        }
        // On the reader rather than on the canvas, so `proxy.size` includes the strip and `fit`
        // frames the drawing into the space it actually occupies. Applied to the canvas alone,
        // the picture would extend under the home indicator while being scaled as if it did not.
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(drawing.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsDetails = true
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showsDetails) { detailsSheet }
    }

    // MARK: - Gestures

    /// Drag to pan.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                transform = pan.pan(transform, by: value.translation.screenPoint)
            }
            .onEnded { _ in pan.end() }
    }

    /// Pinch to zoom around the fingers.
    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                transform = pinch.zoom(
                    transform,
                    by: value.magnification,
                    at: ScreenPoint(
                        x: value.startAnchor.x, y: value.startAnchor.y)
                )
            }
            .onEnded { _ in pinch.end() }
    }

    /// Frames the whole drawing again.
    ///
    /// Takes the size rather than reading `transform.viewSize`, because on first appearance
    /// that still holds the placeholder: `onAppear` can run before the geometry is measured.
    private func fit(to size: CGSize) {
        let target = size.screenSize
        withAnimation(.easeOut(duration: 0.22)) {
            transform = ViewTransform.fitting(drawing.viewport.bounds, in: target)
        }
    }

    /// Zooms about the middle of the view, which is what the toolbar buttons mean.
    private func zoomBy(_ factor: Double) {
        var next = transform
        next.zoom(
            by: factor,
            around: ScreenPoint(
                x: next.viewSize.width / 2, y: next.viewSize.height / 2)
        )
        transform = next
    }

    // MARK: - Chrome

    private var controls: some View {
        VStack(spacing: 0) {
            // By the time anyone taps this, `viewSize` holds the measured size.
            Button { fit(to: transform.cgSize) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Fit drawing")

            Divider().frame(width: 28)

            Button { zoomBy(1.6) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zoom in")

            Divider().frame(width: 28)

            Button { zoomBy(1 / 1.6) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zoom out")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(16)
    }

    /// Shown only when geometry lies outside the initial view, which is what makes a
    /// seemingly empty area make sense.
    @ViewBuilder
    private var outsideHint: some View {
        VStack(spacing: 6) {
            if drawing.viewport.hasGeometryOutside {
                Text("Some geometry is outside the initial view.")
            }
            // The reader does not model every DXF entity type. Saying so on screen matters:
            // a drawing that is quietly missing its tables and 3D solids looks complete, and
            // the reader has no way to tell that something is absent.
            if !drawing.skipped.isEmpty {
                Text(SkippedEntities.summary(drawing.skipped))
            }
            // Layers the file marks as off or frozen are not drawn, which is what a CAD
            // application does. Saying so keeps a thin drawing from looking complete.
            if !drawing.scene.hiddenByLayer.isEmpty {
                Text(SkippedEntities.switchedOff(drawing.scene.hiddenByLayer))
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }


    private var detailsSheet: some View {
        NavigationStack {
            List {
                Section("Drawing") {
                    LabeledContent("File", value: drawing.name)
                    LabeledContent("Entities", value: String(drawing.scene.polylines.count))
                    LabeledContent("Text items", value: String(drawing.scene.texts.count))
                    LabeledContent("Filled areas", value: String(drawing.scene.fills.count))
                }
                Section("Extents") {
                    let bounds = drawing.viewport.fullBounds
                    LabeledContent("Width", value: Self.format(bounds.width))
                    LabeledContent("Height", value: Self.format(bounds.height))
                }
                Section("Read in") {
                    LabeledContent("Time", value: Self.format(drawing.duration) + " s")
                    // `ForEach` needs an identity, and a dictionary's sorted entries are
                    // tuples, which Swift cannot key-path into. A tiny named row type is both
                    // compilable and clearer than `id: \.key` would have been.
                    ForEach(Self.rows(from: drawing.skipped), id: \.entity) { row in
                        LabeledContent(row.entity, value: String(row.count))
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showsDetails = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// One row of the "skipped entities" list.
    private struct SkippedRow: Identifiable {
        var entity: String
        var count: Int
        var id: String { entity }
    }

    /// Skipped entity types, alphabetically, as rows.
    private static func rows(from skipped: [String: Int]) -> [SkippedRow] {
        skipped
            .map { SkippedRow(entity: $0.key, count: $0.value) }
            .sorted { $0.entity < $1.entity }
    }
}
