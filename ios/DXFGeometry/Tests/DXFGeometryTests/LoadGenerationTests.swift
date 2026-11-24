import Testing
@testable import DXFGeometry

/// Overlapping loads. The app can be asked for a second drawing before the first has started,
/// and a timeout from the earlier load must not touch the later one.
@Suite("Load generation")
struct LoadGenerationTests {
    @Test("Each load gets its own generation")
    func distinct() {
        var generations = LoadGeneration()
        let first = generations.begin()
        let second = generations.begin()
        #expect(first != second)
        #expect(generations.isCurrent(second))
        #expect(!generations.isCurrent(first))
    }

    @Test("A stale generation stops being current")
    func stale() {
        var generations = LoadGeneration()
        let first = generations.begin()
        #expect(generations.isCurrent(first))
        _ = generations.begin()
        // The first load's timeout must now do nothing.
        #expect(!generations.isCurrent(first))
    }

    @Test("Generations stay unique and increasing over many loads")
    func monotonic() {
        var generations = LoadGeneration()
        var seen: [Int] = []
        for _ in 0..<50 { seen.append(generations.begin()) }
        #expect(Set(seen).count == 50)
        #expect(seen == seen.sorted())
    }
}
