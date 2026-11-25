// The `os` surface this app uses: a logger, and the privacy marker it passes to it. The message
// is an interpolated string in the real API, so the overload has to accept one.
public struct Logger {
    public init(subsystem: String, category: String) {}

    /// How much of an interpolated value may appear in the log. `Self.log.error("…\(x, privacy: .public)")`
    /// only compiles if the interpolation knows about this.
    public enum Privacy { case `public`, `private` }

    public func error(_ message: String) {}
    public func error(_ message: String, privacy: Privacy) {}
    public func info(_ message: String) {}
    public func debug(_ message: String) {}
}

extension String.StringInterpolation {
    public mutating func appendInterpolation<T>(_ value: T, privacy: Logger.Privacy) {
        appendInterpolation(String(describing: value))
    }
}
