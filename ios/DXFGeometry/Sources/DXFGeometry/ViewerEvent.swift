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

/// Where a bundled resource folder ends up.
///
/// SwiftPM's `.copy("Resources/dwgviewer")` puts the folder in the bundle, but the name it
/// carries depends on how the target is built: sometimes the leaf name, sometimes the path
/// as written. Guessing one and being wrong produces a blank DWG tab with no explanation, so
/// the candidates are tried in order and the failure is explicit.
public enum ResourceLocation {
    /// The file names to try for a resource folder, in order of likelihood.
    ///
    /// - Parameter path: the path as written in `Package.swift`, e.g. `Resources/dwgviewer`.
    public static func candidates(for path: String) -> [String] {
        let leaf = (path as NSString).lastPathComponent
        let withoutExtension = (path as NSString).deletingPathExtension
        var names = [leaf, path, withoutExtension]
        // Deduplicate while keeping order: a path with no directory repeats the leaf.
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Finds the first candidate that exists under `bundleRoot`.
    ///
    /// - Parameters:
    ///   - path: the path as written in `Package.swift`.
    ///   - root: the directory to search, normally the bundle's resource directory.
    ///   - exists: injection point, so the search can be tested without a bundle.
    public static func find(
        path: String,
        in root: String,
        exists: (String) -> Bool
    ) -> String? {
        for name in candidates(for: path) {
            let candidate = (root as NSString).appendingPathComponent(name)
            if exists(candidate) { return candidate }
        }
        return nil
    }
}

/// The zoom limits for a PDF page.
///
/// `scaleFactorForSizeToFit` is only meaningful once the view has a size. Asking for it in
/// `makeUIView` — before layout — yields zero, and limits derived from it would be a floor of
/// 0.01 and a ceiling of 4, which is a pinch range far narrower than the page needs. The
/// arithmetic is here so it can be tested, and so the fallback for an unmeasured view is
/// explicit rather than accidental.
public enum PDFZoom {
    /// How far out and in the reader may pinch, relative to fitting the page.
    public static let minimumRelativeZoom: Double = 0.25
    public static let maximumRelativeZoom: Double = 12

    /// The pinch limits for a page whose fit scale is `fitScale`.
    ///
    /// - Parameter fitScale: `scaleFactorForSizeToFit`, or 0 when the view has no size yet.
    /// - Returns: the floor and ceiling to assign, and whether they came from a real
    ///   measurement.
    public static func limits(fitScale: Double) -> (
        minimum: Double, maximum: Double, measured: Bool
    ) {
        // A view that has not been laid out reports zero, and there is no honest scale to
        // derive from it.
        guard fitScale.isFinite, fitScale > 0 else {
            return (minimum: 0.1, maximum: 10, measured: false)
        }
        let minimum = fitScale * minimumRelativeZoom
        let maximum = fitScale * maximumRelativeZoom
        return (minimum: minimum, maximum: maximum, measured: true)
    }
}

/// Whether a PDF can be shown, decided away from PDFKit.
///
/// `PDFDocument(url:)` returning nil and a document with no pages are different failures with
/// different causes — a file that is not a PDF at all, and one that is but holds nothing — and
/// the reader is told which. The check is here rather than in the viewer because PDFKit cannot
/// be built off an Apple platform, and this is the part that could be wrong.
public enum PDFOpenOutcome: Equatable, Sendable {
    /// Pages to show.
    case readable(pageCount: Int)
    /// The bytes did not parse into a document.
    case notAPDF
    /// It parsed, and holds no pages.
    case noPages

    /// Decides from what PDFKit reported.
    ///
    /// - Parameter pageCount: the document's page count, or nil when PDFKit produced no document.
    public static func verdict(pageCount: Int?) -> PDFOpenOutcome {
        guard let pageCount else { return .notAPDF }
        guard pageCount > 0 else { return .noPages }
        return .readable(pageCount: pageCount)
    }

    /// What to show the reader, or nil when there is something to show instead.
    public var message: String? {
        switch self {
        case .readable: return nil
        case .notAPDF: return "The file is not a readable PDF."
        case .noPages: return "The PDF has no pages."
        }
    }
}
