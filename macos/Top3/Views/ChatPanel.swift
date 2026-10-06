import AppKit
import SwiftUI
import WebKit

/// The AI chat side panel (and pop-out window): a chat site in a web view, with a provider switcher.
/// You sign in inside the page; ProTask never touches the site's cookies, tokens or contents.
struct ChatPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var poppedOut = false
    @AppStorage(ChatSession.noteSeenKey) private var noteSeen = false
    @State private var showNote = false

    private var session: ChatSession { ChatSession.shared }

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            ChatPromptChips()
            Hairline()
            if showNote {
                Text("If Google sign-in is blocked here, log in with email")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { replyOverlay }
        }
        .sheet(item: $session.preview) { request in
            ChatSharePreview(request: request).presentationBackground(Theme.Palette.surface)
        }
        .onAppear {
            session.start()
            // The sign-in note shows on first use only.
            if !noteSeen {
                showNote = true
                noteSeen = true
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.xxs) {
            Menu {
                ForEach(ChatProvider.allCases) { p in
                    Button(p.title) { session.select(p) }
                }
            } label: {
                Text(session.provider.title).font(Theme.Fonts.smallMedium).foregroundStyle(Theme.Palette.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose the chat site")
            .padding(.leading, poppedOut ? Theme.Size.trafficLights : 0)
            Spacer()
            if session.copied {
                Text("Copied").font(Theme.Fonts.secondary).foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.trailing, Theme.Space.xs)
                    .transition(.opacity)
            }
            IconButton(icon: .copy, help: "Copy my tasks for chat (⇧⌘J)") { model.copyTasksForChat() }
            IconButton(icon: .paste, help: "Paste reply: apply the changes in the reply you copied") { model.pasteChatReply() }
            IconButton(icon: .reload, help: "Reload") { session.reload() }
            if !poppedOut {
                IconButton(icon: .popout, help: "Open the chat in its own window") { popOut() }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.Size.header)
        .background(WindowDragArea())
    }

    private func popOut() {
        openWindow(id: "chat")
    }

    // MARK: Reply

    @ViewBuilder private var replyOverlay: some View {
        switch session.flow.state {
        case let .reviewing(plan):
            ChatConfirmCard(plan: plan).transition(.opacity.combined(with: .offset(y: Theme.Space.xs)))
        case let .applied(count, _):
            ChatUndoBar(count: count).transition(.opacity)
        case .idle:
            if let notice = session.notice {
                Text(notice)
                    .font(Theme.Fonts.small)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.elevated))
                    .padding(Theme.Space.m)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if session.needsCustomURL {
            CustomURLPrompt()
        } else {
            ZStack {
                ChatWebView(webView: session.webView)
                if case let .failed(message) = session.state {
                    VStack(spacing: Theme.Space.s) {
                        Text(message).font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textSecondary)
                        Button("Reload") { session.reload() }.buttonStyle(.ghost)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Palette.surface)
                }
            }
        }
    }
}

/// Asks for the Custom provider's address (https only).
private struct CustomURLPrompt: View {
    @State private var text = UserDefaults.standard.string(forKey: ChatSession.customURLKey) ?? ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Web address of the chat site").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Space.s) {
                TextField("https://", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Fonts.small)
                    .frame(width: Theme.Size.customURLField)
                    .onSubmit(open)
                Button("Open", action: open).buttonStyle(.ghost)
            }
            if invalid {
                Text("Use an https address, like https://example.com.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Text("Only that site loads here. Other links open in your browser.")
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func open() {
        invalid = !ChatSession.shared.setCustomURL(text)
    }
}

/// Hosts the shared web view. Moving between the panel and the pop-out window re-parents the same view,
/// so the page (and sign-in) carries over.
struct ChatWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}

/// A thin strip on the panel's leading edge that resizes it.
struct PanelResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Theme.Size.resizeHandle)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        let base = start ?? width
                        start = base
                        width = min(max(base - g.translation.width, Theme.Size.chatPanelMinWidth), Theme.Size.chatPanelMaxWidth)
                    }
                    .onEnded { _ in start = nil }
            )
            .help("Drag to resize")
    }
}

/// The pop-out window's content. Closing it puts the chat back in the side panel.
struct ChatWindowContent: View {
    var body: some View {
        ChatPanel(poppedOut: true)
            .background(Theme.Palette.surface)
            .ignoresSafeArea()
            .background(WindowConfigurator())
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Palette.text)
            .tint(Theme.Palette.accent)
            .onAppear {
                // However the window was opened (Pop out, the Window menu, state restoration), the side panel steps aside.
                ChatSession.shared.poppedOut = true
                UserDefaults.standard.set(false, forKey: AppModel.chatPanelKey)
            }
            .onDisappear {
                ChatSession.shared.poppedOut = false
                UserDefaults.standard.set(true, forKey: AppModel.chatPanelKey)
            }
    }
}
