// A stub of the UIKit pieces the app imports directly.
//
// `PDFViewer` writes `import UIKit` for `UIColor`. Everything else UIKit-shaped that the app
// touches — `UIView`, `UIViewRepresentable` — arrives through the SwiftUI stub, which is where
// a real project gets them too.
public final class UIColor {
    public init() {}
    public static let clear = UIColor()
    public init(red: Double, green: Double, blue: Double, alpha: Double) {}
}
