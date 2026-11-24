import Testing
@testable import DXFGeometry

/// The reader does not model every DXF entity type — tables, 3D solids, multileaders, the
/// infinite construction lines — and a drawing quietly missing them looks complete. This
/// summary is what tells the reader, so its wording matters.
@Suite("Skipped entities")
struct SkippedEntitiesTests {
    @Test("Nothing skipped says nothing")
    func none() {
        #expect(SkippedEntities.summary([:]).isEmpty)
    }

    @Test("One is singular, several are plural")
    func plural() {
        #expect(SkippedEntities.summary(["LIGHT": 1]) == "1 item not shown: LIGHT.")
        #expect(SkippedEntities.summary(["RAY": 2]) == "2 items not shown: RAY.")
    }

    @Test("Names are sorted, so the message does not depend on dictionary order")
    func sorted() {
        let summary = SkippedEntities.summary(["XLINE": 1, "ATTDEF": 2])
        #expect(summary == "3 items not shown: ATTDEF, XLINE.")
    }

    @Test("Past the limit the tail is counted rather than listed")
    func abbreviated() {
        let summary = SkippedEntities.summary(
            ["A": 1, "B": 1, "C": 1, "D": 1, "E": 1])
        #expect(summary.hasPrefix("5 items not shown: A, B, C"))
        #expect(summary.contains(" and 2 more"))
    }

    @Test("Exactly at the limit there is no tail")
    func exact() {
        let summary = SkippedEntities.summary(["A": 1, "B": 1, "C": 1])
        #expect(!summary.contains("more"))
    }

    @Test("A limit of zero still names one type")
    func zeroLimit() {
        #expect(SkippedEntities.summary(["X": 1], shownNames: 0).contains("X"))
    }
}
