import Foundation

/// A point in drawing space.
///
/// The geometry core deliberately does not use CoreGraphics types: it has to compile and
/// be testable on every platform, and a CAD drawing is 2D double precision regardless of
/// what the renderer eventually uses.
public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Point) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

/// An axis-aligned rectangle in drawing space.
public struct Bounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Grows a bounds value to include a point, starting from an empty box.
    public struct Accumulator {
        private var minX = Double.infinity
        private var minY = Double.infinity
        private var maxX = -Double.infinity
        private var maxY = -Double.infinity

        public init() {}

        public mutating func add(_ point: Point) {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        public mutating func add(_ points: [Point]) {
            for point in points { add(point) }
        }

        /// A box padded to be non-empty, so a single point or a horizontal line still has
        /// an area to fit into.
        public var bounds: Bounds? {
            guard minX.isFinite, maxX >= minX, minY.isFinite, maxY >= minY else { return nil }
            return Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        }
    }
}
