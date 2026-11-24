import Foundation

/// What the page reports, translated into what the app should do.
///
/// The DWG viewer is a web page; the app only learns how it is doing from these messages.
/// A message this code mishandles shows up as a spinner that never stops, or an error alert
/// on a drawing that opened fine — neither of which a compile-time check would catch, and
/// neither of which is easy to reproduce without a device. So the translation is plain data
/// and lives here, where it is tested.
public enum ViewerEvent: Equatable, Sendable {
    /// The engine is up and the page is ready for a drawing.
    case ready
    /// A drawing is being converted.
    case loading
    /// The document is open.
    case activated
    /// The first frame is drawn, with how long it took in milliseconds.
    case rendered(milliseconds: Int?)
    /// Something failed; the string is worth showing.
    case failed(String)
    /// A message the app does not act on.
    case ignored

    /// The event name the page posts.
    public var name: String {
        switch self {
        case .ready: return "ready"
        case .loading: return "loading"
        case .activated: return "activated"
        case .rendered: return "rendered"
        case .failed: return "error"
        case .ignored: return ""
        }
    }

    /// Reads an event from a message posted by the page.
    ///
    /// Anything unrecognised is `.ignored` rather than an error: the page may gain events
    /// the app does not care about, and that should not break an open drawing.
    public init(message: [String: Any]) {
        let name = message["event"] as? String ?? ""
        switch name {
        case "ready":
            self = .ready
        case "loading":
            self = .loading
        case "activated":
            self = .activated
        case "rendered":
            // A non-numeric `ms` must not lose the event; the timing is only diagnostics.
            self = .rendered(milliseconds: (message["ms"] as? NSNumber)?.intValue)
        case "error":
            // An error with no message is still an error worth showing.
            let detail = message["message"] as? String
            self = .failed(detail?.isEmpty == false ? detail! : "The DWG viewer failed.")
        default:
            self = .ignored
        }
    }

    /// The loading text this event implies, or `nil` when nothing should be shown.
    ///
    /// `nil` means "no overlay": the drawing is on screen, or the app is showing its own
    /// error instead, and a spinner on top of either would be wrong.
    public var statusText: String? {
        switch self {
        case .ready, .loading: return "Opening the drawing…"
        case .activated, .rendered, .failed, .ignored: return nil
        }
    }

    /// Whether the engine has finished starting up, so the page can be reused for the next
    /// drawing instead of being reloaded.
    public var engineIsWarm: Bool {
        switch self {
        case .ready, .activated, .rendered: return true
        case .loading, .failed, .ignored: return false
        }
    }

    /// The error to show, if this event is an error.
    public var errorMessage: String? {
        if case let .failed(detail) = self { return detail }
        return nil
    }
}

/// How a drawing should be handed to an already-loaded page.
///
/// The page can take one either way: as base64 inside a JavaScript call, or by fetching it
/// from the scheme handler after a reload. The first keeps the wasm engine warm and is much
/// faster; the second always works and is the only sane choice for a large file, because a
/// real DWG is routinely tens of megabytes and base64 adds a third on top of that.
public enum DrawingHandoff: Equatable, Sendable {
    /// Hand the bytes over directly; the page stays loaded.
    case directly
    /// Reload the page and let it fetch the drawing.
    case viaReload

    /// The largest file worth passing as a base64 string.
    ///
    /// 8 MB of file becomes about 11 MB of base64, which is already a slow JavaScript call.
    public static let directLimit = 8 * 1024 * 1024

    /// Decides how to hand a drawing over.
    ///
    /// - Parameters:
    ///   - byteCount: size of the drawing.
    ///   - pageCanAcceptDirectly: whether the page exposes the direct entry point.
    public init(byteCount: Int, pageCanAcceptDirectly: Bool) {
        self = pageCanAcceptDirectly && byteCount <= Self.directLimit
            ? .directly
            : .viaReload
    }
}

/// The generation counter that keeps overlapping loads from interfering.
///
/// The app can be asked for a new drawing before the previous one has finished starting up.
/// Two waits then share one object, and the failure modes are subtle: a timeout from the
/// earlier load must not resume the later load's continuation, and a continuation that is
/// replaced must be resumed rather than dropped, or the task awaiting it hangs forever.
///
/// This type is that rule on its own, so it can be tested without a web view.
public struct LoadGeneration: Equatable, Sendable {
    private var current = 0

    public init() {}

    /// Starts a new load and returns its generation.
    ///
    /// - Returns: The generation to check a timeout against.
    public mutating func begin() -> Int {
        current += 1
        return current
    }

    /// Whether a timeout from `generation` still belongs to the live load.
    public func isCurrent(_ generation: Int) -> Bool {
        generation == current
    }

    /// The generation of the load in progress, or 0 before any.
    public var value: Int { current }
}
