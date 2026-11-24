import Testing
import Foundation
import SwiftDXF
@testable import DXFGeometry

/// Block attributes are the part numbers and titles AutoCAD draws for a reference. They were
/// invisible: the reader models them, but only expands them into entities when asked, and the
/// app never asked — so a drawing of parts came out as outlines with no labels.
///
/// The fixture is the parser's own, which carries four attributes across three references and
/// renders as "ACME", "D-1234 °5", "Plate ⌀20 hole" and "S-7".
@Suite("Block attributes")
struct BlockAttributeTests {
    /// The fixture, which lives in the SwiftDXF checkout beside this package.
    private var fixtureURL: URL {
        get throws {
            try #require(
                Bundle.module.url(forResource: "attributes", withExtension: "dxf"))
        }
    }

    private func load(attributes: Bool) throws -> DrawScene {
        let data = try Data(contentsOf: try fixtureURL)
        var options = DXF.ReadOptions()
        options.expandBlocks = true
        options.expandAttributes = attributes
        let drawing = try DXF.read(data: data, options: options)
        return SceneBuilder().build(drawing)
    }

    @Test("An attribute becomes text when asked")
    func expanded() throws {
        let scene = try load(attributes: true)
        let values = scene.texts.map(\.string)
        #expect(!values.isEmpty, "attributes should produce text")
        // The fixture's part number, which is the kind of label that was missing.
        #expect(values.contains { $0.contains("S-7") }, "got \(values)")
    }

    @Test("And not when it is not asked for")
    func notExpanded() throws {
        let with = try load(attributes: true)
        let without = try load(attributes: false)
        #expect(without.texts.count < with.texts.count)
    }
}
