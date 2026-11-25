import Foundation
import UniformTypeIdentifiers

// A real SwiftUI re-exports Foundation, which is why the app uses `URL` and `Data` after only
// importing SwiftUI. The stub has to do the same or the app appears to be missing them.
@_exported import Foundation

// SwiftUI also re-exports Observation, which is where `@Observable` and `@ObservationIgnored`
// come from. Those are macros: the toolchain supplies the module and its plugin together, so
// this only works on a target that has both — the Linux one in CI, not the local wasm SDK.
#if canImport(Observation)
@_exported import Observation
#endif

/// Owned here rather than in the UIKit stub, which re-exports it: SwiftUI re-exports UIKit's
/// types in the real thing, and declaring it twice makes it ambiguous in modules that see both.
/// The script builds SwiftUI before UIKit, so this is also the only order that resolves.
public final class UIColor {
    public init() {}
    public static let clear = UIColor()
    public static let white = UIColor()
    public static let black = UIColor()
    public static let gray = UIColor()
    public init(red: Double, green: Double, blue: Double, alpha: Double) {}
}

/// A security-scoped URL is an app-platform addition to Foundation, so a Linux toolchain has no
/// such method and the app looks wrong for using one. The app opens files from the document
/// picker, which hands back scoped URLs; declaring it here is what lets the rest be checked.
extension URL {
    public func startAccessingSecurityScopedResource() -> Bool { true }
    public func stopAccessingSecurityScopedResource() {}
}

public struct CGPoint {
    public static let zero = CGPoint()
    public var x: Double
    public var y: Double
    public init() { x = 0; y = 0 }
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct CGSize: Equatable {
    public var width: Double
    public var height: Double
    public init() { width = 0; height = 0 }
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public struct CGRect {
    public var origin: CGPoint
    public var size: CGSize
    public static let zero = CGRect()
    public init() { origin = CGPoint(); size = CGSize() }
    public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
    public func insetBy(dx: Double, dy: Double) -> CGRect { self }
    public func contains(_ point: CGPoint) -> Bool { false }
}

/// `@MainActor` as in the real thing. A view's `body` and its stored state are main-actor
/// isolated, and without the attribute a type whose storage constructs a `@MainActor` model —
/// which both of this app's viewers do — fails to compile under Swift 6.
@MainActor public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension Never: View {
    public var body: Nothing { Nothing() }
}

/// A view with no content, which the builders below return when they cannot name a type.
/// `nonisolated` on purpose: `View` is `@MainActor`, but these builders are called from
/// `nonisolated` static context, so constructing an empty view must not cross actors.
public nonisolated struct Nothing: View {
    public nonisolated init() {}
    public nonisolated var body: Nothing { Nothing() }
}

/// How a change is animated. The app only passes it around, never inspects it.
public struct Animation {
    public static let `default` = Animation()
    public static func easeInOut(duration: Double) -> Animation { Animation() }
    public static func spring(duration: Double) -> Animation { Animation() }
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static func easeIn(duration: Double) -> Animation { Animation() }
    public static func linear(duration: Double) -> Animation { Animation() }
}

/// Runs a state change inside an animation. A free function in the real API, which is why the
/// app calls it without a receiver.
public func withAnimation<Result>(_ animation: Animation? = nil, _ body: () throws -> Result) rethrows -> Result { try body() }

@resultBuilder public struct ViewBuilder {
    public nonisolated static func buildBlock() -> Nothing { Nothing() }
    public nonisolated static func buildBlock(_ views: any View...) -> Nothing { Nothing() }
    public nonisolated static func buildOptional(_ view: Any?) -> Nothing { Nothing() }
    public nonisolated static func buildIf(_ view: Any?) -> Nothing { Nothing() }
    // Not generic on the result: an `if`/`else if` chain with no final `else` leaves nothing
    // to infer a second parameter from. The branches are still type-checked.
    public nonisolated static func buildEither(first: Any) -> Nothing { Nothing() }
    public nonisolated static func buildEither(second: Any) -> Nothing { Nothing() }
    public nonisolated static func buildLimitedAvailability(_ view: Any) -> Nothing { Nothing() }
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
    // Not `@MainActor` here: `View` carries the attribute, so a `@State` declared in a view is
    // already main-actor isolated. Marking the initialiser as well made a plain struct's
    // property initialiser an actor crossing, which is the error this was meant to avoid.
    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public var projectedValue: Binding<Value> { Binding(wrappedValue: box.value) }
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
    /// A binding that is not connected to anything, which is what a stub can offer for the
    /// projected value of state that no one else owns.
    public init(wrappedValue: Value) {
        var v = wrappedValue
        getter = { v }
        setter = { v = $0 }
    }
}

public enum HorizontalAlignment { case center, leading, trailing }
public enum VerticalAlignment { case center, top, bottom }
public enum Alignment { case center, top, bottom, topLeading, bottomTrailing }
public struct UnitPoint {
    public static let bottomLeading = UnitPoint()
    public static let bottomTrailing = UnitPoint()
    public static let topLeading = UnitPoint()
    public static let topTrailing = UnitPoint()
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
    public var body: Nothing { Nothing() }
}

public struct HStack<Content: View>: View {
    public init(
        alignment: VerticalAlignment = .center, spacing: Double? = nil,
        @ViewBuilder content: () -> Content
    ) {}
    public var body: Nothing { Nothing() }
}

public struct ZStack<Content: View>: View {
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
    public var body: Nothing { Nothing() }
}

/// One view per element of a collection, which is how the app lists skipped entities.
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
    public var body: Nothing { Nothing() }
}

/// A label and a value, which is how the app lists skipped entities.
public struct LabeledContent<Content: View, Value: View>: View {
    public init(_ title: String, value: String) where Content == Text, Value == Text {}
    public var body: Nothing { Nothing() }
}

public struct Group<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Nothing { Nothing() }
}

public struct GeometryReader<Content: View>: View {
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {}
    public var body: Nothing { Nothing() }
}

public struct GeometryProxy {
    public var size: CGSize { CGSize() }
}

public struct Spacer: View {
    public init() {}
    public var body: Nothing { Nothing() }
}

public struct Divider: View {
    public init() {}
    public var body: Nothing { Nothing() }
}

public struct Text: View {
    public init(_ s: String) {}
    public var body: Nothing { Nothing() }
    public func font(_ f: Font?) -> Text { self }
    public func foregroundStyle(_ c: Color) -> Text { self }
    public func padding(_ length: Double) -> Text { self }
}

public struct Font {
    public static let caption = Font()
    public static let body = Font()
    public static let footnote = Font()
    public static let title = Font()
    public static func system(size: Double) -> Font { Font() }
    public static func system(size: Double, weight: Font.Weight) -> Font { Font() }
    public struct Weight {}
    public static let title2 = Weight()
    public static let title3 = Weight()
}

public struct Color: View {
    public var body: Nothing { Nothing() }
    public init() {}
    public static let white = Color()
    public static let black = Color()
    public static let clear = Color()
    public static let gray = Color()
    public static let primary = Color()
    public static let secondary = Color()
    public static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color() }

    /// The colour space a literal names, e.g. `Color(.sRGB, red: …)`.
    public enum ColorSpace { case sRGB, displayP3 }
    public nonisolated init(_ space: ColorSpace, red: Double, green: Double, blue: Double, opacity: Double) {}
}

public struct Button<Label: View>: View {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
    public init(_ title: String, action: @escaping () -> Void) where Label == Text {}
    public var body: Nothing { Nothing() }
}

public struct Label<Title: View, Icon: View>: View {
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {}
    public init(_ title: String, systemImage: String) where Title == Text, Icon == Image {}
    public var body: Nothing { Nothing() }
}

public struct Image: View {
    public init(systemName: String) {}
    public var body: Nothing { Nothing() }
}

public struct ProgressView<Label: View>: View {
    public init(@ViewBuilder label: () -> Label) {}
    public init(_ title: String) where Label == Text {}
    public var body: Nothing { Nothing() }
}

/// The sides a padding applies to.
public struct Edge {
    public struct Set: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let all = Set(rawValue: 0)
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
        public static let top = Set(rawValue: 4)
        public static let bottom = Set(rawValue: 8)
        public static let leading = Set(rawValue: 16)
        public static let trailing = Set(rawValue: 32)
    }
}

public struct RoundedRectangle: View {
    public init(cornerRadius: Double) {}
    public var body: Nothing { Nothing() }
}

public struct Capsule: View {
    public init() {}
    public var body: Nothing { Nothing() }
}

public struct Rectangle: View {
    public init() {}
    public var body: Nothing { Nothing() }
}

public final class GraphicsContext {
    public struct Shading {
        public static func color(_ c: Color) -> Shading { Shading() }
    }
    public enum Style {}
    public func fill(_ path: Path, with shading: Shading) {}
    public mutating func fill(_ path: Path, with shading: Shading, style: FillStyle) {}
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {}
    public func translateBy(x: Double, y: Double) {}
    public func rotate(by angle: Angle) {}
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint) {}
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
    public init(_ rect: CGRect) {}
    public init() {}
    public mutating func move(to point: CGPoint) {}
    public mutating func addLine(to point: CGPoint) {}
    public mutating func addPath(_ path: Path) {}
    public mutating func closeSubpath() {}
}

public struct Canvas: View {
    public init(
        opaque: Bool = false, colorMode: ColorMode = .nonLinear,
        rendersAsynchronously: Bool = false,
        renderer: @escaping (GraphicsContext, CGSize) -> Void
    ) {}
    public enum ColorMode { case nonLinear, linear }
    public var body: Nothing { Nothing() }
}

public struct DragGesture {
    public init(minimumDistance: Double) {}
    public func onChanged(_ action: @escaping (Value) -> Void) -> DragGesture { self }
    public func onEnded(_ action: @escaping (Value) -> Void) -> DragGesture { self }
    public struct Value {
        public var translation: CGSize { CGSize() }
        public var location: CGPoint { CGPoint() }
    }
}

public struct MagnifyGesture {
    public init(minimumScaleDelta: Double) {}
    public func onChanged(_ action: @escaping (Value) -> Void) -> MagnifyGesture { self }
    public func onEnded(_ action: @escaping (Value) -> Void) -> MagnifyGesture { self }
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
    public func font(_ f: Font?) -> some View { Nothing() }
    public func tint(_ c: Color?) -> some View { Nothing() }
    public func background(_ c: Color) -> some View { Nothing() }
    public func background(_ s: Material, in shape: Shape) -> some View { Nothing() }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V)
        -> some View { Nothing() }
    public func onAppear(perform action: (() -> Void)? = nil) -> some View { Nothing() }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { Nothing() }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View { Nothing() }
    public func onChange<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View { Nothing() }
    public func animation(_ a: Animation? = nil, value: some Equatable) -> some View { Nothing() }

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

/// The translucent surface the app puts behind its status pill.
public struct Material: ShapeStyle {
    public static var ultraThinMaterial: Material { Material() }
    public static var thinMaterial: Material { Material() }
    public static var regularMaterial: Material { Material() }
}
extension Color: ShapeStyle {}

public protocol ButtonStyle {}

public struct PlainButtonStyle: ButtonStyle {}

extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

public protocol Gesture {}
extension DragGesture: Gesture {}
extension MagnifyGesture: Gesture {}

public struct NavigationStack<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Nothing { Nothing() }
}

public struct List<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: Nothing { Nothing() }
}

public struct Section<Content: View, Header: View>: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {}
    public init(_ title: String, @ViewBuilder content: () -> Content) where Header == Text {}
    public var body: Nothing { Nothing() }
}


public struct ToolbarItem<Content: View>: View {
    public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {}
    public var body: Nothing { Nothing() }
}

public struct ToolbarItemPlacement {
    public static let topBarLeading = ToolbarItemPlacement()
    public static let topBarTrailing = ToolbarItemPlacement()
    public static let navigationBarLeading = ToolbarItemPlacement()
    public static let navigationBarTrailing = ToolbarItemPlacement()
}

public struct ContentUnavailableView<LabelContent: View, Description: View>: View {
    public init(
        @ViewBuilder label: () -> LabelContent, @ViewBuilder description: () -> Description
    ) {}
    public var body: Nothing { Nothing() }
}

public struct Alert: View {
    public init(
        title: Text, message: Text? = nil, dismissButton: Alert.Button? = nil
    ) {}
    public struct Button {}
    public static func `default`(_ title: Text) -> Button { Button() }
    public var body: Nothing { Nothing() }
}

public enum TaskPriority { case userInitiated, background }

open class UIView {
    public var frame: CGRect = CGRect()
    public var bounds: CGRect = CGRect()
    public var superview: UIView? { nil }
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

public struct Context {}

public protocol UIViewRepresentable: View {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    func makeUIView(context: Context) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: Context)
    func makeCoordinator() -> Coordinator
}

extension UIViewRepresentable {
    public var body: Nothing { Nothing() }
    public func makeCoordinator() -> Void {}
}

// `UTType` belongs to UniformTypeIdentifiers; naming it here as well would make it ambiguous
// for anything that imports both. The script builds that module after this one, so the member is
// declared there and this file does not repeat it.
