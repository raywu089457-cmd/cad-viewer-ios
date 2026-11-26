import Foundation

/// Which engine renders a given file.
///
/// DXF is parsed and drawn natively, because SwiftDXF is pure Swift and its geometry
/// becomes a SwiftUI canvas directly. DWG has no open native parser, so it goes to the
/// bundled web viewer running the LibreDWG wasm build inside a `WKWebView`. PDF needs no
/// third party at all: the system's `PDFKit` already reads and renders it.
///
/// This lives here, next to the geometry, rather than in the app target, so the routing
/// decision can be tested on a machine without an Apple SDK. It is the kind of logic that
/// fails silently: a file that opens a blank canvas instead of an error.
public enum DrawingKind: Equatable, Sendable {
    case dxf
    case dwg
    case pdf
    case unsupported(extension: String)

    public init(fileName: String) {
        // `pathExtension` handles "floor.plan.v2.dxf" and a name with no dot, and lowercased
        // because iOS hands over whatever the file was called.
        //
        // Whitespace is trimmed first. A file that arrives by download, cloud sync or a
        // paste often keeps a trailing space — `report.dxf ` — and without the trim
        // `pathExtension` answers `"dxf "`, which is no engine's extension. The file is a
        // perfectly ordinary DXF and the app refused it, which looks like a broken app
        // rather than a bad name.
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (trimmed as NSString).pathExtension.lowercased()
        switch ext {
        case "dxf": self = .dxf
        case "dwg": self = .dwg
        case "pdf": self = .pdf
        default: self = .unsupported(extension: ext)
        }
    }

    /// Whether the app has an engine for this type.
    public var canRender: Bool {
        if case .unsupported = self { return false }
        return true
    }

    /// The extension as written, for messages. Empty when the name has none.
    public var fileExtension: String {
        if case let .unsupported(ext) = self { return ext }
        switch self {
        case .dxf: return "dxf"
        case .dwg: return "dwg"
        case .pdf: return "pdf"
        case .unsupported: return ""
        }
    }
}

/// Why a file could not be shown.
///
/// Modelled as data rather than as an error string so the message can be built — and
/// tested — without a file system or a UI.
/// What a DWG says it is, in its first six bytes.
///
/// Every DWG begins with `AC` and a four-digit version: `AC1015` is R2000, `AC1027` is R2013,
/// `AC1032` is R2018. The bundled engine does not check this — it accepts any bytes and reports
/// that it drew them — so a text file renamed to `.dwg` opens to a blank canvas presented as a
/// drawing. Checking the signature is the only format check the DWG path can have, and it is
/// cheap enough to do before handing the bytes over.
public enum DWGHeader {
    /// The version the bytes claim, or nil when they do not begin with one.
    ///
    /// - Parameter bytes: the first few bytes of the file; six is enough.
    public static func version(of bytes: Data) -> String? {
        // Six bytes is the whole signature; a file shorter than that cannot be a DWG.
        guard bytes.count >= 6 else { return nil }
        let signature = String(decoding: bytes.prefix(6), as: Unicode.ASCII.self)
        guard signature.hasPrefix("AC") else { return nil }
        let digits = signature.dropFirst(2)
        // Four digits, so `ACME Corp` in a text file is not mistaken for a version, and within the
        // range AutoCAD has actually used: `AC1006` (R10) through `AC1032` (R2018) and no further.
        // Accepting anything above would let `AC9999` through, which is not a format that exists.
        guard digits.count == 4, digits.allSatisfy({ $0.isNumber }) else { return nil }
        guard let number = Int(digits), (1006...1032).contains(number) else { return nil }
        return signature
    }

    /// Whether these bytes are a DWG at all.
    public static func looksLikeDWG(_ bytes: Data) -> Bool {
        version(of: bytes) != nil
    }
}
public struct LoadFailure: Error, Identifiable, Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The extension is not one the app can show. The string is what the name had.
        case unsupportedType(String)
        /// The file could not be read or parsed; the string is a detail worth showing.
        case unreadable(String)
        case empty
        /// A DXF that is really a binary DXF, which SwiftDXF does not read.
        case binaryDXF
        /// The file parsed, but it holds nothing to draw.
        case noGeometry
        /// The file could not be read for a reason the reader can act on: gone, unreadable,
        /// outside the sandbox. Distinct from ``unreadable``, which passes a parser's own
        /// detail through — a Cocoa error description is written for a developer, and the
        /// reader is not one.
        case cannotRead(FileReadFailure)
        /// The file has geometry, but all of it is on layers it marks as off or frozen.
        ///
        /// Distinct from ``noGeometry`` because the two need different sentences: one says the
        /// file is thin, the other says the file is fine and the layers are switched off, which
        /// is something the reader can go and change.
        case allLayersSwitchedOff([String])
    }

    public let id: UUID
    public var fileName: String
    public var reason: Reason

    public init(fileName: String, reason: Reason) {
        self.id = UUID()
        self.fileName = fileName
        self.reason = reason
    }

    /// What to show the reader.
    public var message: String {
        switch reason {
        case .unsupportedType(let ext):
            return ext.isEmpty
                ? "This file has no extension, so its type is unknown."
                : ".\(ext) files cannot be shown here."
        case .unreadable(let detail):
            return detail
        case let .cannotRead(failure):
            return failure.message
        case .empty:
            return "The file is empty."
        case .binaryDXF:
            return "This is a binary DXF. Save it as ASCII DXF to open it here."
        case .noGeometry:
            return "The file parsed, but it holds no model-space geometry."
        case let .allLayersSwitchedOff(layers):
            // Sorted and joined here rather than at the call site so the sentence is the same
            // wherever it is produced, and so a test can read it without a view.
            let names = layers.sorted().prefix(3).joined(separator: ", ")
            let more = layers.count > 3 ? " and \(layers.count - 3) more" : ""
            return "Every drawing in this file is on a layer that is switched off or frozen: "
                + "\(names)\(more). Turn the layers on to see them."
        }
    }

    /// The alert title: names the file when there is one.
    public var title: String {
        fileName.isEmpty
            ? "Could not open the file"
            : "Could not open \(fileName)"
    }
}

/// Whether a file-picker failure is just the reader changing their mind.
///
/// `fileImporter` reports cancellation as a failure, with `NSUserCancelledError`. Showing
/// "Could not open the file" when someone taps Cancel is a false error: nothing went wrong,
/// and an unexpected alert trains people to dismiss alerts without reading them.
public enum FilePickOutcome {
    /// The Cocoa error code for a cancelled user action.
    public static let cancelledCode = 3072

    /// Whether an error means the picker was dismissed.
    public static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == cancelledCode {
            return true
        }
        // URLSession and other layers wrap it; check the underlying chain too.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSCocoaErrorDomain && underlying.code == cancelledCode
        }
        return false
    }
}

/// Why a file could not be read off disk, in the reader's terms rather than the system's.
///
/// `Data(contentsOf:)` fails with a Cocoa error whose description names a domain and a code.
/// Shown to someone who tapped a file in the picker, that is noise: it says a developer's
/// thing went wrong, not that the file they chose is gone. These are the four cases that
/// actually happen, each with something to do about it.
public enum FileReadFailure: Equatable, Sendable {
    /// The file is not there — deleted, moved, or a stale reference from a previous session.
    case missing
    /// The file exists but this app may not read it: permissions, or a sandbox it never got.
    case notPermitted
    /// The volume is unreadable: an ejected drive, a disconnected share.
    case volumeUnavailable
    /// Anything else. The system's own words are kept, because a detail that names the real
    /// problem is better than a sentence that says "something went wrong".
    case other(String)

    public var message: String {
        switch self {
        case .missing:
            return "The file is no longer there. It may have been moved or deleted since you "
                + "picked it."
        case .notPermitted:
            return "The app is not allowed to read this file. Copy it into the app's folder, "
                + "or pick it again."
        case .volumeUnavailable:
            return "The place this file lives is not available right now. Reconnect the drive "
                + "or download the file again."
        case let .other(detail):
            return detail
        }
    }

    /// Classifies a read error. `NSCocoaError` codes are the only portable signal here, so
    /// this works on both the simulator and a device without knowing which volume it is.
    public static func classify(_ error: Error) -> FileReadFailure {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else {
            return .other(nsError.localizedDescription)
        }
        // The constants are spelled out because the wasm SDK the harness builds against does
        // not export `NSFileReadVolumeUnavailableError`, and a library that cannot be compiled
        // everywhere it is used is not portable. The values are Cocoa's and do not change.
        switch nsError.code {
        case 260, 4:  // NSFileReadNoSuchFileError, NSFileNoSuchFileError
            return .missing
        case 257, 513:  // NSFileReadNoPermissionError, NSFileWriteNoPermissionError
            return .notPermitted
        case 259, 256:  // NSFileReadVolumeUnavailableError, NSFileReadUnknownError
            return .volumeUnavailable
        default:
            return .other(nsError.localizedDescription)
        }
    }
}
