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

/// The same rule as the DWG viewer, applied to opening files: a slow parse must not land on
/// top of the file the reader chose afterwards.
extension LoadGenerationTests {
    @Test("A load abandoned for a second file does not land")
    func abandonedLoad() {
        var generation = LoadGeneration()
        // open() calls reset(), which invalidates anything in flight, then takes its own.
        _ = generation.begin()
        let slow = generation.begin()

        // The reader picks another file before the first finishes.
        _ = generation.begin()
        let chosen = generation.begin()

        #expect(!generation.isCurrent(slow))
        #expect(generation.isCurrent(chosen))
    }

    @Test("Closing the document discards a pending load")
    func closing() {
        var generation = LoadGeneration()
        let pending = generation.begin()
        // reset() bumps, so the pending result is dropped.
        _ = generation.begin()
        #expect(!generation.isCurrent(pending))
    }
}
