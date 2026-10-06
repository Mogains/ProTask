import XCTest

/// The chat panel only moves around the chosen site; everything else goes to the browser.
final class ChatProviderTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testMainFrameStaysOnTheProvidersSites() {
        let d = ChatProvider.claude.domains
        XCTAssertEqual(ChatProvider.route(url("https://claude.ai/chat/123"), isMainFrame: true, domains: d), .allow)
        XCTAssertEqual(ChatProvider.route(url("https://www.anthropic.com/legal"), isMainFrame: true, domains: d), .allow)
        XCTAssertEqual(ChatProvider.route(url("https://example.com/"), isMainFrame: true, domains: d), .external)
        XCTAssertEqual(ChatProvider.route(url("https://claude.ai.evil.com/"), isMainFrame: true, domains: d), .external)
        XCTAssertEqual(ChatProvider.route(url("https://evilclaude.ai/"), isMainFrame: true, domains: d), .external)
        XCTAssertEqual(ChatProvider.route(url("http://claude.ai/"), isMainFrame: true, domains: d), .external, "https only")
    }

    func testFramesAndNonWebSchemes() {
        let d = ChatProvider.chatgpt.domains
        XCTAssertEqual(ChatProvider.route(url("https://challenges.cloudflare.com/x"), isMainFrame: false, domains: d), .allow)
        XCTAssertEqual(ChatProvider.route(url("about:blank"), isMainFrame: true, domains: d), .allow)
        XCTAssertEqual(ChatProvider.route(url("mailto:a@b.c"), isMainFrame: true, domains: d), .external)
        XCTAssertEqual(ChatProvider.route(url("file:///etc/passwd"), isMainFrame: true, domains: d), .block)
        XCTAssertEqual(ChatProvider.route(url("javascript:alert(1)"), isMainFrame: false, domains: d), .block)
        XCTAssertEqual(ChatProvider.route(url("zoommtg://join"), isMainFrame: true, domains: d), .block)
    }

    func testCustomAddress() {
        XCTAssertEqual(ChatProvider.customURL(from: "chat.example.com")?.absoluteString, "https://chat.example.com")
        XCTAssertNil(ChatProvider.customURL(from: "http://chat.example.com"))
        XCTAssertNil(ChatProvider.customURL(from: "https://user:pass@chat.example.com"))
        XCTAssertNil(ChatProvider.customURL(from: "localhost"))
        XCTAssertNil(ChatProvider.customURL(from: "not a url"))
        let u = ChatProvider.customURL(from: "https://chat.example.com/app")
        XCTAssertEqual(ChatProvider.customDomains(for: u), ["chat.example.com"])
        XCTAssertNil(ChatProvider.customDomains(for: nil).first)
    }
}
