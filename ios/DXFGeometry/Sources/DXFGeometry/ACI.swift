import Foundation

/// The AutoCAD Color Index (ACI) palette.
///
/// DXF stores colours as an index into a fixed 256-entry table, not as RGB. Indices
/// 10…249 are generated: 24 hues at 15° steps, each with ten shades (five value
/// levels, half of them desaturated towards white). Rather than shipping a 256-row
/// literal, this reproduces the generating scheme, which is what the published
/// table encodes.
public enum ACI {
    /// Index 7 is context-dependent: white on a dark background, black on a light one.
    public static let byLayer = 256
    /// Index 0 means "inherit from the enclosing block reference".
    public static let byBlock = 0

    /// The RGB for an ACI index, as components in `0...1`.
    ///
    /// - Parameters:
    ///   - index: ACI index; values outside `1...255` fall back to index 7.
    ///   - onDarkBackground: Whether index 7 should be white (`true`) or black.
    public static func rgb(_ index: Int, onDarkBackground: Bool = true) -> RGB {
        switch index {
        case 1: return RGB(1, 0, 0)
        case 2: return RGB(1, 1, 0)
        case 3: return RGB(0, 1, 0)
        case 4: return RGB(0, 1, 1)
        case 5: return RGB(0, 0, 1)
        case 6: return RGB(1, 0, 1)
        case 7: return onDarkBackground ? RGB(1, 1, 1) : RGB(0, 0, 0)
        case 8: return RGB(0.5, 0.5, 0.5)
        case 9: return RGB(0.75, 0.75, 0.75)
        case 250: return RGB(51 / 255, 51 / 255, 51 / 255)
        case 251: return RGB(80 / 255, 80 / 255, 80 / 255)
        case 252: return RGB(105 / 255, 105 / 255, 105 / 255)
        case 253: return RGB(130 / 255, 130 / 255, 130 / 255)
        case 254: return RGB(190 / 255, 190 / 255, 190 / 255)
        case 255: return RGB(1, 1, 1)
        case 10...249:
            let hue = Double((index - 10) / 10) * 15 // 0…345 in 15° steps
            // Ten shades per hue: five value levels, each with a plain and a
            // half-desaturated variant.
            let levels: [Double] = [1, 1, 0.65, 0.65, 0.5, 0.5, 0.3, 0.3, 0.15, 0.15]
            let shade = (index - 10) % 10
            let base = hsv(hue: hue, saturation: 1, value: levels[shade])
            return shade % 2 == 0 ? base : mix(base, with: .white, amount: 0.5)
        default:
            return rgb(7, onDarkBackground: onDarkBackground)
        }
    }

    /// HSV → RGB, with components in `0...1`.
    static func hsv(hue: Double, saturation s: Double, value v: Double) -> RGB {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let sector = Int(h.rounded(.down))
        let f = h - Double(sector)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch sector % 6 {
        case 0: return RGB(v, t, p)
        case 1: return RGB(q, v, p)
        case 2: return RGB(p, v, t)
        case 3: return RGB(p, q, v)
        case 4: return RGB(t, p, v)
        default: return RGB(v, p, q)
        }
    }

    static func mix(_ a: RGB, with b: RGB, amount: Double) -> RGB {
        RGB(
            a.r + (b.r - a.r) * amount,
            a.g + (b.g - a.g) * amount,
            a.b + (b.b - a.b) * amount
        )
    }
}

/// A colour with components in `0...1`.
public struct RGB: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let white = RGB(1, 1, 1)
    public static let black = RGB(0, 0, 0)

    /// A stable key for grouping entities that are drawn in the same colour.
    ///
    /// Quantised to a 0–255 channel, because the renderer shows eight bits per channel and two
    /// colours that differ below that are the same on screen. Using the raw doubles as a
    /// dictionary key would also work, but two entities that resolved to the same ACI index
    /// through different layers can carry values that differ in the last bit.
    public var packed: Int {
        let red = Int((r.clampedForColour * 255).rounded())
        let green = Int((g.clampedForColour * 255).rounded())
        let blue = Int((b.clampedForColour * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }
}

extension Double {
    /// Clamped into the range a colour channel can hold, so a malformed value cannot trap.
    fileprivate var clampedForColour: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}
