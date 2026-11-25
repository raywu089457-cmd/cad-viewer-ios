import Foundation

/// Whether a parsed drawing holds anything the reader can see.
///
/// A truncated DXF is the case this exists for: its header survives, so the extents are
/// present and a viewport can be framed around them, and the app would otherwise show a blank
/// canvas and report the file as opened. Distinguishing "parsed but empty" from "opened" is
/// what lets the reader be told.
public enum LoadReadiness {
    /// What a parsed file turned out to hold.
    public enum Verdict: Equatable, Sendable {
        /// There is geometry to draw.
        case drawable
        /// The file parsed but nothing in it can be shown.
        case empty
    }

    /// Decides from the scene's extent and sample points.
    ///
    /// - Parameters:
    ///   - samplePoints: every point of every primitive.
    ///   - hasBounds: whether the scene produced extents, which a header alone can provide.
    public static func verdict(
        samplePoints: [Point],
        hasBounds: Bool
    ) -> Verdict {
        // Points are what the renderer draws. Extents can come from the header of a file whose
        // entities never arrived, so they are not evidence of anything visible.
        guard !samplePoints.isEmpty else { return .empty }
        // A scene with points but no bounds should not happen; treat it as empty rather than
        // framing a drawing the viewport cannot describe.
        guard hasBounds else { return .empty }
        return .drawable
    }
}
