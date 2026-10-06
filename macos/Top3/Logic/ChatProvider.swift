import Foundation

/// The chat sites the AI panel can show. ProTask only loads the page: you sign in inside it, like in a browser,
/// and the app never reads its cookies, tokens or contents.
enum ChatProvider: String, CaseIterable, Identifiable {
    case claude, chatgpt, gemini, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .gemini: "Gemini"
        case .custom: "Custom"
        }
    }

    /// Start page, or nil for Custom (the address comes from Settings or the panel).
    var home: URL? {
        switch self {
        case .claude: URL(string: "https://claude.ai/new")
        case .chatgpt: URL(string: "https://chatgpt.com/")
        case .gemini: URL(string: "https://gemini.google.com/app")
        case .custom: nil
        }
    }

    /// Sites the panel may navigate to (and their subdomains), including each one's sign-in pages.
    /// Every other link opens in the default browser.
    var domains: [String] {
        switch self {
        case .claude: ["claude.ai", "claude.com", "anthropic.com", "accounts.google.com"]
        case .chatgpt: ["chatgpt.com", "openai.com", "accounts.google.com"]
        case .gemini: ["gemini.google.com", "accounts.google.com", "consent.google.com"]
        case .custom: []
        }
    }

    /// A web address typed for Custom: https only, a real host name, no user name or password in it.
    static func customURL(from text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let url = URL(string: t), url.scheme?.lowercased() == "https",
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Domains for Custom: the host of its address.
    static func customDomains(for url: URL?) -> [String] {
        url?.host.map { [$0.lowercased()] } ?? []
    }

    static func allows(_ url: URL, domains: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    enum Route: Equatable {
        case allow      // load it in the panel
        case external   // open it in the default browser instead
        case block      // drop it
    }

    /// Where a navigation goes. Pages inside frames (sign-in widgets, captchas) may load; the page itself
    /// only moves within the provider's sites. Non-web schemes never run in the panel.
    static func route(_ url: URL, isMainFrame: Bool, domains: [String]) -> Route {
        switch url.scheme?.lowercased() {
        case "about", "blob", "data":
            return .allow
        case "https", "http":
            if !isMainFrame { return .allow }
            return allows(url, domains: domains) ? .allow : .external
        case "mailto":
            return isMainFrame ? .external : .block
        default:
            return .block
        }
    }
}
