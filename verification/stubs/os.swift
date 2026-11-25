// A stub of `os`, which the app uses only for `Logger`.
public struct Logger {
    public init(subsystem: String, category: String) {}
    public func error(_ message: String) {}
    public func info(_ message: String) {}
    public func debug(_ message: String) {}
    public enum Privacy { case `public`, `private` }
}
