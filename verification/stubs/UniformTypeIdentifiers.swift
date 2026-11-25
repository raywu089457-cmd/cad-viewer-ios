// A stub of UniformTypeIdentifiers, as the app uses it: identifiers from Info.plist, named
// rather than derived from a file extension.
public struct UTType {
    public let identifier: String
    public init?(_ identifier: String) { self.identifier = identifier }
    public init(filenameExtension: String) { identifier = filenameExtension }
    public static let pdf = UTType("com.adobe.pdf")!
    public static let data = UTType("public.data")!
    public static let image = UTType("public.image")!
}
