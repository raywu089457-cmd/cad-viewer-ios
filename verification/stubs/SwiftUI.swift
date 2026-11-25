import Foundation

// A real SwiftUI re-exports Foundation, which is why the app uses `URL` and `Data` after only
// importing SwiftUI. The stub has to do the same or the app appears to be missing them.
@_exported import Foundation

public struct CGPoint {
    public var x: Double
    public var y: Double
    public init() { x = 0; y = 0 }
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct CGSize {
    public var width: Double
    public var height: Double
    public init() { width = 0; height = 0 }
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct CGRect {
    public var origin: CGPoint
    public var size: CGSize
    public init() { origin = CGPoint(); size = CGSize() }
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public func insetBy(dx: Double, dy: Double) -> CGRect { self }
    public func contains(_ point: CGPoint) -> Bool { false }
}

public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension Never: View {
    public var body: Never { fatalError() }
}

public struct Nothing: View {
    public init() {}
    public var body: Never { fatalError() }
}

@resultBuilder public struct ViewBuilder {
    public static func buildBlock() -> Nothing { Nothing() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> Nothing { Nothing() }
    public static func buildBlock<C0: View, C1: View, C2: View>(
        _ c0: C0, _ c1: C1, _ c2: C2) -> Nothing { Nothing() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> Nothing { Nothing() }
    public static func buildOptional<C: View>(_ c: C?) -> Nothing { Nothing() }
    public static func buildIf<C: View>(_ c: C?) -> Nothing { Nothing() }
    public static func buildEither<C: View>(first: C) -> C { first }
    public static func buildEither<C: View>(second: C) -> C { second }
}

@propertyWrapper public final class State<Value> {
    private final class Box {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private let box: Box
    public var wrappedValue: Value {
        get { box.value }
        set { box.value = newValue }
    }
    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public init(initialValue: Value) { box = Box(initialValue) }
}

@propertyWrapper public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value) -> Void
    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = set
    }
}

public enum HorizontalAlignment { case center, leading, trailing }
public enum VerticalAlignment { case center, top, bottom }
public enum Alignment { case center, top, bottom, topLeading, bottomTrailing }
public struct UnitPoint {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let center = UnitPoint(x: 0.5, y: 0.5)
}

public struct VStack<Content: View>: View {
    public init(
        alignment: HorizontalAlignment = .center, spacing: Double? = nil,
        @ViewBuilder content: () -> Content
    ) {}
    public var body: Never { fatalError() }
}

public struct HStack<Content: View>: View {
    public init(
        alignment: VerticalAlignment = .center, spacing: Double? = nil,
        @ViewBuilder content: () -> Content
    ) {}
    public var body: Never { fatalError() }
}

public struct ZStack<Content: View>: View {
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError() }
}

public struct Group<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError() }
}

public struct GeometryReader<Content: View>: View {
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {}
    public var body: Never { fatalError() }
}

public struct GeometryProxy {
    public var size: CGSize { CGSize() }
}

public struct Spacer: View {
    public init() {}
    public var body: Never { fatalError() }
}

public struct Divider: View {
    public init() {}
    public var body: Never { fatalError() }
}

public struct Text: View {
    public init(_ s: String) {}
    public var body: Never { fatalError() }
    public func font(_ f: Font?) -> Text { self }
    public func foregroundStyle(_ c: Color) -> Text { self }
    public func padding(_ length: Double) -> Text { self }
}

public struct Font {
    public static func system(size: Double) -> Font { Font() }
    public static func system(size: Double, weight: Font.Weight) -> Font { Font() }
    public struct Weight {}
    public static let title2 = Weight()
    public static let title3 = Weight()
}

public struct Color {
    public static let white = Color()
    public static let black = Color()
    public static let clear = Color()
    public static let gray = Color()
    public static let primary = Color()
    public static let secondary = Color()
    public static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color() }
}

public struct Button<Label: View>: View {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
    public init(_ title: String, action: @escaping () -> Void) where Label == Text {}
    public var body: Never { fatalError() }
}

public struct Label<Title: View, Icon: View>: View {
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {}
    public init(_ title: String, systemImage: String) where Title == Text, Icon == Image {}
    public var body: Never { fatalError() }
}

public struct Image: View {
    public init(systemName: String) {}
    public var body: Never { fatalError() }
}

public struct ProgressView<Label: View>: View {
    public init(@ViewBuilder label: () -> Label) {}
    public init(_ title: String) where Label == Text {}
    public var body: Never { fatalError() }
}

public struct RoundedRectangle: View {
    public init(cornerRadius: Double) {}
    public var body: Never { fatalError() }
}

public struct Capsule: View {
    public init() {}
    public var body: Never { fatalError() }
}

public struct Rectangle: View {
    public init() {}
    public var body: Never { fatalError() }
}

public struct GraphicsContext {
    public struct Shading {}
    public enum Style {}
    public mutating func fill(_ path: Path, with shading: Color) {}
    public mutating func fill(_ path: Path, with shading: Color, style: FillStyle) {}
    public mutating func stroke(_ path: Path, with shading: Color, style: StrokeStyle) {}
    public mutating func translateBy(x: Double, y: Double) {}
    public mutating func rotate(by angle: Angle) {}
    public mutating func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint) {}
}

public struct FillStyle {
    public init(eoFill: Bool = false) {}
}

public struct StrokeStyle {
    public init(lineWidth: Double = 1, lineCap: LineCap = .butt, lineJoin: LineJoin = .miter) {}
    public enum LineCap { case butt, round, square }
    public enum LineJoin { case miter, round, bevel }
}

public struct Angle {
    public static func radians(_ value: Double) -> Angle { Angle() }
}

public struct Path {
    public init() {}
    public mutating func move(to point: CGPoint) {}
    public mutating func addLine(to point: CGPoint) {}
    public mutating func addPath(_ path: Path) {}
    public mutating func closeSubpath() {}
}

public struct Canvas<Symbols: View>: View {
    public init(
        opaque: Bool = false, colorMode: ColorMode = .nonLinear,
        rendersAsynchronously: Bool = false,
        renderer: @escaping (inout GraphicsContext, CGSize) -> Void
    ) {}
    public enum ColorMode { case nonLinear, linear }
    public var body: Never { fatalError() }
}

public struct DragGesture {
    public init(minimumDistance: Double) {}
    public struct Value {
        public var translation: CGSize { CGSize() }
        public var location: CGPoint { CGPoint() }
    }
}

public struct MagnifyGesture {
    public init(minimumScaleDelta: Double) {}
    public struct Value {
        public var magnification: Double { 1 }
        public var startAnchor: UnitPoint { .center }
    }
}

extension View {
    public func padding(_ length: Double = 0) -> some View { Nothing() }
    public func padding(_ edges: Edge.Set, _ length: Double = 0) -> some View { Nothing() }
    public func frame(width: Double? = nil, height: Double? = nil) -> some View { Nothing() }
    public func frame(maxWidth: Double? = nil, maxHeight: Double? = nil) -> some View { Nothing() }
    public func foregroundStyle(_ c: Color) -> some View { Nothing() }
    public func background(_ c: Color) -> some View { Nothing() }
    public func background<S: ShapeStyle>(_ s: S, in shape: S) -> some View { Nothing() }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V)
        -> some View { Nothing() }
    public func onAppear(perform action: (() -> Void)? = nil) -> some View { Nothing() }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { Nothing() }
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping () async -> Void)
        -> some View { Nothing() }
    public func alert<S: StringProtocol, A: View>(
        _ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A
    ) -> some View { Nothing() }
    public func alert<S: StringProtocol, A: View, M: View>(
        _ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> some View { Nothing() }
    public func sheet<V: View>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V)
        -> some View { Nothing() }
    public func navigationTitle<S: StringProtocol>(_ title: S) -> some View { Nothing() }
    public func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode)
        -> some View { Nothing() }
    public func toolbar<C: View>(@ViewBuilder content: () -> C) -> some View { Nothing() }
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { Nothing() }
    public func gesture<G: Gesture>(_ gesture: G) -> some View { Nothing() }
    public func simultaneousGesture<G: Gesture>(_ gesture: G) -> some View { Nothing() }
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View
        { Nothing() }
    public func contentShape<S: Shape>(_ shape: S) -> some View { Nothing() }
    public func id<ID: Hashable>(_ id: ID) -> some View { Nothing() }
    public func disabled(_ disabled: Bool) -> some View { Nothing() }
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View { Nothing() }
    public func controlSize(_ size: ControlSize) -> some View { Nothing() }
    public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View { Nothing() }
    public func fileImporter(
        isPresented: Binding<Bool>, allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View { Nothing() }
    public func onOpenURL(perform action: @escaping (URL) -> Void) -> some View { Nothing() }
}

public enum Edge { public struct Set {} }
public enum ControlSize { case regular, large, small }
public struct PresentationDetent: Hashable { public static let medium = PresentationDetent() }
public enum NavigationBarItem {
    public enum TitleDisplayMode { case automatic, inline, large }
}

public protocol Shape: View {}
extension RoundedRectangle: Shape {}
extension Capsule: Shape {}
extension Rectangle: Shape {}

public protocol ShapeStyle {}
extension Color: ShapeStyle {}

public protocol ButtonStyle {}

public protocol Gesture {}
extension DragGesture: Gesture {}
extension MagnifyGesture: Gesture {}

public struct NavigationStack<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError() }
}

public struct List<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError() }
}

public struct Section<Content: View, Header: View>: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {}
    public init(_ title: String, @ViewBuilder content: () -> Content) where Header == Text {}
    public var body: Never { fatalError() }
}

public struct LabeledContent<Content: View, Label: View>: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {}
    public init(_ title: String, value: String) where Content == Text, Label == Text {}
    public var body: Never { fatalError() }
}

public struct ToolbarItem<Content: View>: View {
    public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {}
    public var body: Never { fatalError() }
}

public struct ToolbarItemPlacement {
    public static let topBarLeading = ToolbarItemPlacement()
    public static let topBarTrailing = ToolbarItemPlacement()
    public static let navigationBarLeading = ToolbarItemPlacement()
    public static let navigationBarTrailing = ToolbarItemPlacement()
}

public struct ContentUnavailableView<Label: View, Description: View>: View {
    public init(
        @ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description
    ) {}
    public var body: Never { fatalError() }
}

public struct Alert: View {
    public init(
        title: Text, message: Text? = nil, dismissButton: Alert.Button? = nil
    ) {}
    public struct Button {}
    public static func `default`(_ title: Text) -> Button { Button() }
    public var body: Never { fatalError() }
}

public enum TaskPriority { case userInitiated, background }

public final class UIView {
    public var frame: CGRect = CGRect()
    public var autoresizingMask: AutoresizingMask = []
    public var backgroundColor: UIColor? = nil
    public init() {}
    public func addSubview(_ view: UIView) {}

    public struct AutoresizingMask: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let flexibleWidth = AutoresizingMask(rawValue: 1)
        public static let flexibleHeight = AutoresizingMask(rawValue: 2)
    }
}

public final class UIColor {
    public init() {}
    public static let clear = UIColor()
    public init(red: Double, green: Double, blue: Double, alpha: Double) {}
}

public struct Context {}

public protocol UIViewRepresentable: View {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    func makeUIView(context: Context) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: Context)
    func makeCoordinator() -> Coordinator
}

extension UIViewRepresentable {
    public var body: Never { fatalError() }
    public func makeCoordinator() -> Void {}
}

public struct UTType {
    public init?(_ identifier: String) { return nil }
    public static let pdf = UTType()
    public static let data = UTType()
    public init(filenameExtension: String) { self.init() }
    public init() {}
}
