// `PDFViewer` writes `import UIKit` for `UIColor`. The real UIKit is a superset of what SwiftUI
// re-exports, so rather than declare the type twice — which makes it ambiguous in any module
// that sees both — the SwiftUI stub owns it and this one re-exports it, exactly as UIKit does
// in relation to SwiftUI.
//
// Keeping it here instead would mean SwiftUI importing UIKit to name a member of its own folded
// in view, and the script builds SwiftUI first.
@_exported import SwiftUI
