import AppKit
import Observation
import WebKit

/// The AI chat panel's web view. One instance moves between the side panel and the pop-out window.
///
/// Hard rules: the app never reads, copies or stores the chat site's cookies, tokens or page contents
/// (no cookie store access, no injected scripts), makes no network calls of its own, and logs nothing.
/// Sign-in state lives in ProTask's own persistent website data store, like a browser profile.
@MainActor
@Observable
final class ChatSession: NSObject {
    static let shared = ChatSession()

    static let providerKey = "chatProvider"
    static let customURLKey = "chatCustomURL"
    static let noteSeenKey = "chatSignInNoteSeen"

    /// Fixed id of ProTask's own website data store (~/Library/WebKit/com.anmolbhatt.top3/WebsiteDataStore/…).
    /// Not a secret: it only names the folder, like a browser profile name.
    private static let storeID = UUID(uuidString: "6F1C3E52-1B7A-4C1E-9D0B-5A2E8C4F7B10")!

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var provider: ChatProvider
    private(set) var customURL: URL?
    private(set) var state: LoadState = .idle
    /// Shown in its own window instead of the side panel.
    var poppedOut = false
    /// "Send my tasks" waiting on the preview sheet (first use, or sharing still off).
    var preview: ChatPreviewRequest?
    /// Briefly true after a copy, for the "Copied" confirmation.
    var copied = false

    @ObservationIgnored private var _webView: WKWebView?

    override init() {
        let d = UserDefaults.standard
        provider = d.string(forKey: Self.providerKey).flatMap(ChatProvider.init(rawValue:)) ?? .claude
        customURL = d.string(forKey: Self.customURLKey).flatMap(ChatProvider.customURL(from:))
        super.init()
    }

    var webView: WKWebView {
        if let w = _webView { return w }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeID)
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let w = WKWebView(frame: .zero, configuration: config)
        w.navigationDelegate = self
        w.uiDelegate = self
        w.allowsBackForwardNavigationGestures = true
        _webView = w
        return w
    }

    var home: URL? { provider == .custom ? customURL : provider.home }

    var domains: [String] { provider == .custom ? ChatProvider.customDomains(for: customURL) : provider.domains }

    /// Custom was chosen but has no valid address yet.
    var needsCustomURL: Bool { provider == .custom && customURL == nil }

    /// Loads the provider's page the first time the panel appears.
    func start() {
        guard state == .idle else { return }
        load()
    }

    func select(_ p: ChatProvider) {
        provider = p
        UserDefaults.standard.set(p.rawValue, forKey: Self.providerKey)
        load()
    }

    /// Returns false when the address isn't a valid https URL.
    @discardableResult
    func setCustomURL(_ text: String) -> Bool {
        guard let url = ChatProvider.customURL(from: text) else { return false }
        customURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.customURLKey)
        if provider == .custom { load() }
        return true
    }

    func load() {
        guard let url = home else {
            state = .idle
            return
        }
        state = .loading
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if webView.url == nil || state != .loaded { load() } else { webView.reload() }
    }

    private func fail(_ error: Error) {
        let ns = error as NSError
        // Cancelled loads and our own policy decisions (links sent to the browser) aren't failures.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        let offline: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed]
        state = .failed(ns.domain == NSURLErrorDomain && offline.contains(ns.code)
            ? "You're offline."
            : "Couldn't load \(provider == .custom ? "the page" : provider.title).")
    }
}

struct ChatPreviewRequest: Identifiable {
    let id = UUID()
    var prompt: ChatPrompt?
}

extension ChatSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        switch ChatProvider.route(url, isMainFrame: action.targetFrame?.isMainFrame ?? true, domains: domains) {
        case .allow:
            decisionHandler(.allow)
        case .external:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .block:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if case .failed = state { state = .loading }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .loaded
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension ChatSession: WKUIDelegate {
    /// Links that open a new window: the provider's own pages load here, everything else in the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            switch ChatProvider.route(url, isMainFrame: true, domains: domains) {
            case .allow: webView.load(action.request)
            case .external: NSWorkspace.shared.open(url)
            case .block: break
            }
        }
        return nil
    }

    /// File attachments: the standard open panel, so only files you pick are shared with the page.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.begin { response in completionHandler(response == .OK ? panel.urls : nil) }
    }
}
