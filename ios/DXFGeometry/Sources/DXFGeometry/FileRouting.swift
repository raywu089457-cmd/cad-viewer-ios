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
        let ext = (fileName as NSString).pathExtension.lowercased()
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
        case .empty:
            return "The file is empty."
        case .binaryDXF:
            return "This is a binary DXF. Save it as ASCII DXF to open it here."
        case .noGeometry:
            return "The file parsed, but it holds no model-space geometry."
        }
    }

    /// The alert title: names the file when there is one.
    public var title: String {
        fileName.isEmpty
            ? "Could not open the file"
            : "Could not open \(fileName)"
    }
}
