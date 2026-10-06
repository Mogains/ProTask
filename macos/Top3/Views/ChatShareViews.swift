import SwiftUI

/// The "Share task data with chat" switch and the per-section toggles. Used in Settings and the preview sheet.
struct ChatShareOptions: View {
    @AppStorage(AppModel.chatShareKey) private var share = false
    @AppStorage("chatIncludeTop3") private var top3 = true
    @AppStorage("chatIncludeLists") private var lists = true
    @AppStorage("chatIncludeWaiting") private var waiting = true
    @AppStorage("chatIncludeIdeas") private var ideas = true
    @AppStorage("chatIncludeEvents") private var events = true
    @AppStorage("chatIncludeNotes") private var notes = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Toggle("Share task data with chat", isOn: $share).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                Text("Share task data with chat").foregroundStyle(Theme.Palette.text)
            }
            Text("Copied text goes to whichever chat site you paste it into, under that site's terms. ProTask never sends it anywhere itself.")
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: Theme.Space.xs) {
                box("Top 3", $top3)
                box("Open tasks by list", $lists)
                box("Waiting On", $waiting)
                box("Parking Lot ideas", $ideas)
                box("Today's calendar", $events)
                box("Task notes (shortened)", $notes)
            }
            .disabled(!share)
            .opacity(share ? 1 : Theme.Opacity.disabled)
        }
        .font(Theme.Fonts.small)
    }

    private func box(_ title: String, _ on: Binding<Bool>) -> some View {
        Toggle(title, isOn: on).toggleStyle(.checkbox).foregroundStyle(Theme.Palette.textSecondary)
    }
}

/// Shows exactly what will be copied, before the first copy and whenever sharing is off.
struct ChatSharePreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ChatPreviewRequest
    // Read here too so the preview updates as the toggles change.
    @AppStorage(AppModel.chatShareKey) private var share = false
    @AppStorage("chatIncludeTop3") private var top3 = true
    @AppStorage("chatIncludeLists") private var lists = true
    @AppStorage("chatIncludeWaiting") private var waiting = true
    @AppStorage("chatIncludeIdeas") private var ideas = true
    @AppStorage("chatIncludeEvents") private var events = true
    @AppStorage("chatIncludeNotes") private var notes = true

    private var text: String {
        let sections = ChatSnapshot.Sections(top3: top3, lists: lists, waiting: waiting, ideas: ideas, events: events, notes: notes)
        return ChatSnapshot.build(model.chatSnapshotInput(), sections: sections, prompt: request.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(request.prompt?.title ?? "Copy my tasks for chat")
                .font(Theme.Fonts.bodyMedium)
                .padding(Theme.Space.l)
            Hairline()
            ChatShareOptions().padding(Theme.Space.l)
            Hairline()
            ScrollView {
                Text(share ? text : "Turn on sharing to see what will be copied.")
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(share ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.l)
            }
            .frame(height: Theme.Size.chatPreviewHeight)
            .background(Theme.Palette.background)
            Hairline()
            HStack(spacing: Theme.Space.s) {
                Text("Nothing is pasted into the chat for you.")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button("Copy") {
                    UserDefaults.standard.set(true, forKey: AppModel.chatPreviewSeenKey)
                    model.copyToClipboard(text)
                    dismiss()
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!share)
            }
            .padding(Theme.Space.m)
        }
        .frame(width: Theme.Size.sheetWidth)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
    }
}

/// One-tap prompts above the chat. Each copies the snapshot plus a short instruction.
struct ChatPromptChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(ChatPrompt.allCases) { p in
                    Button(p.title) { model.copyTasksForChat(prompt: p) }
                        .buttonStyle(.ghost)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                            .strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
                        .help("Copy your tasks with this request, then paste it into the chat")
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
        }
    }
}
