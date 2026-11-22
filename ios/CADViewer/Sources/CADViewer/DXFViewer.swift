import SwiftUI
import DXFGeometry

/// The DXF reading surface: the drawing, its gestures, and the zoom controls.
struct DXFViewer: View {
    var drawing: LoadedDrawing

    @State private var transform: ViewTransform
    /// The transform when the current gesture began. Gesture deltas apply to this base
    /// rather than to the previous frame, which is what stops a pinch from drifting.
    @State private var gestureBase: ViewTransform?
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
            .onTapGesture(count: 2) { fit() }
            .onAppear { fit() }
            .onChange(of: proxy.size) { _, newSize in
                transform.resize(to: newSize.screenSize)
            }
            .overlay(alignment: .bottomTrailing) { controls }
            .overlay(alignment: .top) { outsideHint }
        }
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
                let base = gestureBase ?? transform
                if gestureBase == nil { gestureBase = base }
                var next = base
                next.pan(by: value.translation.screenPoint)
                transform = next
            }
            .onEnded { _ in gestureBase = nil }
    }

    /// Pinch to zoom around the fingers.
    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let base = gestureBase ?? transform
                if gestureBase == nil { gestureBase = base }
                var next = base
                // `startAnchor` is normalised, so scale it back to screen points.
                let anchor = ScreenPoint(
                    x: value.startAnchor.x * next.viewSize.width,
                    y: value.startAnchor.y * next.viewSize.height
                )
                next.zoom(by: value.magnification, around: anchor)
                transform = next
            }
            .onEnded { _ in gestureBase = nil }
    }

    /// Frames the whole drawing again.
    private func fit() {
        withAnimation(.easeOut(duration: 0.22)) {
            transform = ViewTransform.fitting(
                drawing.viewport.bounds, in: transform.viewSize)
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
            Button(action: fit) {
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
        if drawing.viewport.hasGeometryOutside {
            Text("Some geometry is outside the initial view.")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
        }
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
                    if !drawing.skipped.isEmpty {
                        ForEach(
                            drawing.skipped.sorted(by: { $0.key < $1.key }), id: \.key
                        ) { entry in
                            LabeledContent(entry.key, value: String(entry.value))
                        }
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
}
