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
