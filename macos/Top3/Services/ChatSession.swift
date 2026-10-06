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
    /// Pasted reply: review, approve, undo.
    var flow = ChatConfirmFlow()
    /// A one-line message in the panel, e.g. when the clipboard has no protask-actions block.
    var notice: String?

    @ObservationIgnored private var _webView: WKWebView?
    /// Open sign-in popups (e.g. "Sign in with Google"), each in its own small window.
    @ObservationIgnored private var popups: [ChatPopup] = []

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
        // Identify as Safari (it is the same WebKit engine). Google refuses sign-in from user agents
        // that look like an embedded web view.
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
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
        let url = action.request.url
        let route = url.map { ChatProvider.route($0, isMainFrame: true, domains: domains) } ?? .allow
        switch route {
        case .external:
            if let url { NSWorkspace.shared.open(url) }
            return nil
        case .block:
            return nil
        case .allow:
            // A real popup built from WebKit's configuration keeps window.opener, which sign-in flows
            // need to hand the result back to the page. Loading it in the panel instead breaks them.
            let popup = ChatPopup(configuration: configuration, features: windowFeatures, domains: domains) { [weak self] closed in
                self?.popups.removeAll { $0 === closed }
            }
            popups.append(popup)
            return popup.webView
        }
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

/// A popup opened by the chat page, such as a sign-in window. Same rules as the panel: only the provider's
/// sites load in it, everything else goes to the browser. It closes when the page calls window.close().
@MainActor
final class ChatPopup: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private let domains: [String]
    private let onClose: (ChatPopup) -> Void

    init(configuration: WKWebViewConfiguration, features: WKWindowFeatures, domains: [String],
         onClose: @escaping (ChatPopup) -> Void) {
        self.domains = domains
        self.onClose = onClose
        webView = WKWebView(frame: .zero, configuration: configuration)
        let width = features.width.map { CGFloat(truncating: $0) } ?? 500
        let height = features.height.map { CGFloat(truncating: $0) } ?? 640
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(width, 400), height: max(height, 500)),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.title = "Sign in"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        switch ChatProvider.route(url, isMainFrame: action.targetFrame?.isMainFrame ?? true, domains: domains) {
        case .allow: decisionHandler(.allow)
        case .external:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .block: decisionHandler(.cancel)
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onClose(self)
    }
}
