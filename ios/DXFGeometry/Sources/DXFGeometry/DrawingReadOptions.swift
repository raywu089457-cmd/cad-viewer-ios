import Foundation
import SwiftDXF

/// The read options the app opens drawings with.
///
/// This exists because the settings are not incidental: they decide whether block geometry
/// appears at all, whether paper space is drawn, and whether the part numbers on a block are
/// visible. A test that used the defaults would be exercising a configuration the app never
/// runs, so the options live here and both the app and the tests use them.
public enum DrawingReadOptions {
    /// What the app uses to open a drawing.
    ///
    /// - `expandBlocks`: a drawing's geometry usually lives in blocks, referenced by
    ///   `INSERT`. Without this, a plan comes out as its top-level lines only.
    /// - `skipPaperSpace`: a phone screen showing a title block scaled to a whole sheet is
    ///   not what "open this drawing" means. Model space is what the drawing is.
    /// - `expandAttributes`: the part numbers and titles a block carries, which AutoCAD
    ///   draws and a reader must show.
    public static var app: DXF.ReadOptions {
        var options = DXF.ReadOptions()
        options.expandBlocks = true
        options.skipPaperSpace = true
        options.expandAttributes = true
        return options
    }

    /// The bare defaults, for a test that is specifically about what those do.
    ///
    /// Named rather than written as `DFX.ReadOptions()` at the call site, so a test that opts
    /// out of the app's settings has to say so.
    public static var bare: DXF.ReadOptions { DXF.ReadOptions() }
}
