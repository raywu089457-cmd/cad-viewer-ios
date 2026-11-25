// A stub of the WebKit surface this app uses. Nothing here loads anything; the point is that
// the compiler resolves the app's own names, signatures and protocols against it.
import Foundation
import SwiftUI
import UIKit

public protocol WKNavigationDelegate: AnyObject {}
public protocol WKUIDelegate: AnyObject {}

public protocol WKScriptMessageHandler: AnyObject {
    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage)
}

public final class WKScriptMessage {
    public var body: Any { fatalError() }
    public init() {}
}

public final class WKUserContentController {
    public init() {}
    public func add(_ handler: WKScriptMessageHandler, name: String) {}
    public func removeScriptMessageHandler(forName name: String) {}
}

public final class WKWebViewConfiguration {
    public init() {}
    public var preferences: Preferences = Preferences()
    public var defaultWebpagePreferences: DefaultWebpagePreferences = DefaultWebpagePreferences()
    public var userContentController: WKUserContentController = WKUserContentController()
    public func setURLSchemeHandler(_ handler: WKURLSchemeHandler?, forURLScheme scheme: String) {}

    public final class Preferences {
        public init() {}
        public var isElementFullscreenEnabled: Bool = false
    }
    public final class DefaultWebpagePreferences {
        public init() {}
        public var allowsContentJavaScript: Bool = true
    }
}

public protocol WKURLSchemeHandler: AnyObject {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask)
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask)
}

/// The wasm Foundation has no `FoundationNetworking`, which is where these two live. Only their
/// shape matters to the signatures the app uses.
public struct URLRequest {
    public var url: URL?
    public init(url: URL) { self.url = url }
}

public typealias URLResponse = SwiftUI.URLResponse

public protocol WKURLSchemeTask: AnyObject {
    var request: URLRequest { get }
    func didReceive(_ response: URLResponse)
    func didReceive(_ data: Data)
    func didFinish()
    func didFailWithError(_ error: Error)
}

public class WKNavigation {}
public class WKNavigationAction {}
public class WKWindowFeatures {}

public final class WKWebView: UIView {
    public var navigationDelegate: WKNavigationDelegate?
    public var uiDelegate: WKUIDelegate?
    public var scrollView: ScrollView = ScrollView()
    public var isOpaque: Bool = true
    // `frame`, `bounds`, `backgroundColor` and `autoresizingMask` are inherited from UIView, as
    // they are in the real framework; declaring them again is an illegal override.
    public var configuration: WKWebViewConfiguration { WKWebViewConfiguration() }
    public init(frame: SwiftUI.CGRect, configuration: WKWebViewConfiguration) {}
    public func load(_ request: URLRequest) -> WKNavigation? { nil }
    public func stopLoading() {}
    public func evaluateJavaScript(_ script: String) async throws -> Any? { nil }
}

public final class ScrollView {
    public init() {}
    public var isScrollEnabled: Bool = true
    public var bounces: Bool = true
    /// A scroll view is a view, and the app tinting it is the same property.
    public var backgroundColor: UIColor? = nil
}
