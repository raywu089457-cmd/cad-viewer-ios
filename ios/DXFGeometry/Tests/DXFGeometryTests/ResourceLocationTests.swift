import Testing
@testable import DXFGeometry

/// Where a bundled resource folder ends up. SwiftPM's `.copy("Resources/dwgviewer")` puts the
/// folder in the bundle, but the name it carries depends on how the target is built; guessing
/// one and being wrong produces a blank DWG tab with no explanation.
@Suite("Resource location")
struct ResourceLocationTests {
    private func find(_ existing: [String]) -> String? {
        ResourceLocation.find(
            path: "Resources/dwgviewer", in: "/app", exists: { existing.contains($0) })
    }

    @Test("Both plausible names are candidates")
    func candidates() {
        let names = ResourceLocation.candidates(for: "Resources/dwgviewer")
        #expect(names.contains("dwgviewer"))
        #expect(names.contains("Resources/dwgviewer"))
        #expect(names.count == Set(names).count)
    }

    @Test("A bare name yields a single candidate")
    func bareName() {
        // There is no directory to strip, so it must not be listed twice.
        #expect(ResourceLocation.candidates(for: "dwgviewer") == ["dwgviewer"])
    }

    @Test("It finds the folder under either layout")
    func bothLayouts() {
        #expect(find(["/app/dwgviewer"]) == "/app/dwgviewer")
        #expect(find(["/app/Resources/dwgviewer"]) == "/app/Resources/dwgviewer")
    }

    @Test("The leaf name wins when both exist")
    func prefersLeaf() {
        #expect(
            find(["/app/dwgviewer", "/app/Resources/dwgviewer"]) == "/app/dwgviewer")
    }

    @Test("An absent folder is reported, not guessed at")
    func absent() {
        #expect(find([]) == nil)
        #expect(find(["/app/other"]) == nil)
    }
}
