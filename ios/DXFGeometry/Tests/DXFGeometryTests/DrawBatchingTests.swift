import Testing
@testable import DXFGeometry

/// Grouping the scene's polylines by colour, so the canvas issues three stroke commands
/// instead of sixteen hundred.
///
/// Grouped by resolved colour rather than by ACI index: two entities can share index 256 —
/// ByLayer — and resolve to different layers and therefore different colours. Grouping by
/// index painted 354 lines of one real drawing in the wrong colour.
@Suite("Draw batching")
struct DrawBatchingTests {
    private let red = RGB(1, 0, 0)
    private let green = RGB(0, 1, 0)
    private let blue = RGB(0, 0, 1)

    @Test("Groups keep drawing order")
    func order() {
        let groups = DrawBatching.groups(colors: [red, red, green, red, blue, green])
        #expect(groups[red.packed] == [0, 1, 3])
        #expect(groups[green.packed] == [2, 5])
        #expect(groups[blue.packed] == [4])
        #expect(groups.count == 3)
    }

    @Test("Every polyline appears exactly once")
    func nothingLost() {
        let colors = [red, red, green, red, blue, green]
        let groups = DrawBatching.groups(colors: colors)
        #expect(groups.values.reduce(0) { $0 + $1.count } == colors.count)
    }

    @Test("Culled polylines are left out")
    func culling() {
        let groups = DrawBatching.groups(
            colors: [red, red, green, red, blue, green],
            visible: [true, false, true, true, false, true])
        #expect(groups[red.packed] == [0, 3])
        #expect(groups[blue.packed] == nil)
    }

    @Test("The same index in two colours is two groups")
    func separateColours() {
        let white = RGB(1, 1, 1)
        let yellow = RGB(1, 1, 0)
        let groups = DrawBatching.groups(colors: [white, yellow, white])
        #expect(groups.count == 2)
        #expect(groups[white.packed] == [0, 2])
        #expect(groups[yellow.packed] == [1])
    }

    @Test("Nothing groups to nothing")
    func empty() {
        #expect(DrawBatching.groups(colors: []).isEmpty)
    }
}

/// The packing that makes a colour usable as a group key.
@Suite("Colour packing")
struct ColourPackingTests {
    @Test("The extremes")
    func extremes() {
        #expect(RGB(1, 1, 1).packed == 0xFF_FFFF)
        #expect(RGB(0, 0, 0).packed == 0)
    }

    @Test("Components are clamped, so a bad value cannot trap")
    func clamping() {
        // Red above 1, green below 0, blue in the middle.
        #expect(RGB(2, -1, 0.5).packed == (255 << 16) | (0 << 8) | 128)
    }

    @Test("A non-finite component becomes zero")
    func nonFinite() {
        #expect(RGB(.nan, .infinity, 0).packed == 0)
    }

    @Test("Distinct colours pack distinctly")
    func distinct() {
        let colours = [
            RGB(1, 0, 0), RGB(0, 1, 0), RGB(0, 0, 1),
            RGB(1, 1, 0), RGB(0, 1, 1), RGB(1, 0, 1), RGB(1, 1, 1)
        ]
        #expect(Set(colours.map(\.packed)).count == colours.count)
    }
}
