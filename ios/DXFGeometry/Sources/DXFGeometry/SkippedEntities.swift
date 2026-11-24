import Foundation

/// What was not drawn, said in one line.
///
/// The reader does not model every DXF entity type: tables, 3D solids, regions, multileaders
/// and the infinite construction lines are all skipped. A drawing that is quietly missing
/// them looks complete, and nothing else on screen would say otherwise, so the reader is told.
public enum SkippedEntities {
    /// A one-line summary, or an empty string when nothing was skipped.
    ///
    /// - Parameters:
    ///   - skipped: entity type to count, as the reader reports it.
    ///   - shownNames: how many type names to list before abbreviating.
    public static func summary(
        _ skipped: [String: Int],
        shownNames: Int = 3
    ) -> String {
        let total = skipped.values.reduce(0, +)
        guard total > 0 else { return "" }

        let names = skipped.keys.sorted()
        let limit = max(shownNames, 1)
        let shown = names.prefix(limit).joined(separator: ", ")
        let remaining = names.count - min(limit, names.count)
        let more = remaining > 0 ? " and \(remaining) more" : ""
        let plural = total == 1 ? "" : "s"
        return "\(total) item\(plural) not shown: \(shown)\(more)."
    }
}

/// Groups drawable primitives so the renderer issues as few commands as possible.
///
/// SwiftUI's canvas costs a command per stroke, and a drawing of 1652 polylines in three
/// colours would otherwise be 1652 commands. Grouping by colour makes it three, with the
/// same output: a path may hold as many disconnected runs as it likes.
public enum DrawBatching {
    /// The colours present, each with the indices of the polylines drawn in it.
    ///
    /// - Parameters:
    ///   - colors: the resolved colour index of each polyline, in drawing order.
    ///   - visible: whether each polyline survives culling; `nil` means all do.
    /// - Returns: colour index to polyline indices, keeping drawing order within a colour.
    public static func groups(
        colors: [Int],
        visible: [Bool]? = nil
    ) -> [Int: [Int]] {
        var groups: [Int: [Int]] = [:]
        for (index, color) in colors.enumerated() {
            if let visible, index < visible.count, !visible[index] { continue }
            groups[color, default: []].append(index)
        }
        return groups
    }
}
