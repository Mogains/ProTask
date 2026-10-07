import AppKit
import SwiftData
import SwiftUI

// MARK: - Loading

/// Decoded Vision images, kept in memory while the app runs. File names are unique per image, so entries never go stale.
@MainActor
final class VisionImageCache {
    static let shared = VisionImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func cached(_ fileName: String) -> NSImage? { cache.object(forKey: fileName as NSString) }

    /// Reads and decodes off the main thread. Nil for a missing or unreadable file.
    func load(_ fileName: String, store: VisionImageStore = .standard) async -> NSImage? {
        if let hit = cached(fileName) { return hit }
        guard let url = store.url(for: fileName) else { return nil }
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }
}

/// A stored Vision image, filling its frame. Shows the placeholder (usually the thumbnail) while the file loads.
struct VisionImageView: View {
    let fileName: String
    var placeholder: String?
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let shown = image ?? VisionImageCache.shared.cached(fileName) ?? placeholder.flatMap(VisionImageCache.shared.cached) {
                Image(nsImage: shown)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Theme.Palette.elevated)
            }
        }
        .task(id: fileName) {
            if let placeholder, VisionImageCache.shared.cached(placeholder) == nil {
                _ = await VisionImageCache.shared.load(placeholder)
            }
            image = await VisionImageCache.shared.load(fileName)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Section

/// The goal's pictures: thumbnails with the cover marked, set cover and remove, and three ways to add.
struct GoalImagesSection: View {
    @Environment(AppModel.self) private var model
    let goal: Goal
    let images: [GoalImage]
    /// Imports still running (drop or paste).
    let importing: Int
    let paste: () -> Void
    let choose: () -> Void

    var body: some View {
        PanelSection(title: "Images", detail: images.isEmpty ? nil : "\(images.count)") {
            HStack(spacing: Theme.Space.xxs) {
                IconButton(icon: .paste, help: "Paste an image (⌘V)", action: paste)
                IconButton(icon: .add, help: "Choose images…", action: choose)
            }
        } content: {
            if images.isEmpty {
                emptyDropZone
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: Theme.GoalPanel.thumbColumns),
                          spacing: Theme.Space.s) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { i, image in
                        GoalImageThumb(image: image, index: i, count: images.count, isCover: image.id == goal.coverImageID, goal: goal)
                    }
                }
            }
            Text(importing > 0 ? "Adding…" : "Resized, without location data, and kept on this Mac.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private var emptyDropZone: some View {
        Button(action: choose) {
            VStack(spacing: Theme.Space.s) {
                Icon(.image, size: Theme.Size.sidebarIcon)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("Drop images here, paste, or choose files")
                    .font(Theme.Fonts.small)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.l)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.background))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose images")
    }
}

/// One square thumbnail. Click to view full size; the menu (hover, right-click or VoiceOver) sets the cover or removes it.
private struct GoalImageThumb: View {
    @Environment(AppModel.self) private var model
    let image: GoalImage
    let index: Int
    let count: Int
    let isCover: Bool
    let goal: Goal

    @State private var hovering = false
    @FocusState private var menuFocused: Bool

    var body: some View {
        Button(action: open) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { VisionImageView(fileName: image.thumbnailFileName) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(hovering ? Theme.Palette.textTertiary : Theme.Palette.border, lineWidth: Theme.Size.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            if isCover {
                Text("Cover")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.text)
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, Theme.Size.hairline)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.elevated))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
                    .padding(Theme.Space.xs)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            PopUpMenuButton(help: "Image actions") { menu } label: {
                Icon(.more)
                    .foregroundStyle(Theme.Palette.text)
                    .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.elevated))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
            }
            .focused($menuFocused)
            .padding(Theme.Space.xxs)
            .opacity(hovering || menuFocused ? 1 : 0)
            .accessibilityLabel("Actions for image \(index + 1)")
        }
        .onHover { h in withAnimation(Theme.Motion.hover) { hovering = h } }
        .contextMenu {
            Button("Show Full Size", action: open)
            Button("Set as Cover") { model.setCover(image, for: goal) }.disabled(isCover)
            Divider()
            Button("Remove Image") { model.removeImage(image) }
        }
        .help(isCover ? "Cover image. Click to show full size" : "Click to show full size")
        .accessibilityLabel("Image \(GalleryIndex.label(index, count: count))\(isCover ? ", cover" : "")")
        .accessibilityAction(named: "Set as cover") { model.setCover(image, for: goal) }
        .accessibilityAction(named: "Remove") { model.removeImage(image) }
    }

    private var menu: [MenuChoice] {
        [.item("Show Full Size", action: open),
         .item("Set as Cover", checked: isCover, enabled: !isCover) { model.setCover(image, for: goal) },
         .separator,
         .item("Remove Image") { model.removeImage(image) }]
    }

    private func open() {
        model.visionBoard.viewer = ImageViewerRequest(goalID: goal.id, imageID: image.id)
    }
}

// MARK: - Viewer

/// A goal's pictures full size over the board. Left and Right arrows move between them; Esc (or a click outside) closes.
struct GoalImageViewer: View {
    @Environment(AppModel.self) private var model
    let request: ImageViewerRequest

    @Query private var images: [GoalImage]
    @Query private var goals: [Goal]
    @FocusState private var focused: Bool

    init(request: ImageViewerRequest) {
        self.request = request
        let id = request.goalID
        _images = Query(filter: #Predicate<GoalImage> { $0.goalID == id }, sort: \GoalImage.sortOrder)
        _goals = Query(filter: #Predicate<Goal> { $0.id == id })
    }

    private var index: Int? { images.firstIndex { $0.id == request.imageID } }

    var body: some View {
        let goal = goals.first
        ZStack {
            Theme.Vision.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            if let index, let goal {
                let image = images[index]
                VStack(spacing: Theme.Space.m) {
                    topBar(goal: goal, image: image, index: index)
                    HStack(spacing: Theme.Space.m) {
                        sideButton(.chevronLeft, help: "Previous image (←)", enabled: index > 0) { step(-1) }
                        VisionImageView(fileName: image.fileName, placeholder: image.thumbnailFileName, contentMode: .fit)
                            .aspectRatio(CGFloat(max(image.pixelWidth, 1)) / CGFloat(max(image.pixelHeight, 1)), contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
                            .shadow(color: Theme.Palette.shadow, radius: Theme.Space.l, y: Theme.Space.xs)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityElement()
                            .accessibilityLabel(image.caption.isEmpty ? "Image \(GalleryIndex.label(index, count: images.count))" : image.caption)
                        sideButton(.chevronRight, help: "Next image (→)", enabled: index < images.count - 1) { step(1) }
                    }
                    if !image.caption.isEmpty {
                        Text(image.caption)
                            .font(Theme.Fonts.small)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .padding(Theme.GoalPanel.viewerPadding)
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.space) { close(); return .handled }
        .onExitCommand(perform: close)
        .onAppear { focused = true }
        .onChange(of: images.count) { if index == nil { close() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image viewer")
        .accessibilityAddTraits(.isModal)
    }

    private func topBar(goal: Goal, image: GoalImage, index: Int) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(goal.title)
                .font(Theme.Fonts.smallMedium)
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
            Text(GalleryIndex.label(index, count: images.count))
                .font(Theme.Fonts.small)
                .foregroundStyle(Theme.Palette.textTertiary)
                .monospacedDigit()
            Spacer()
            if image.id == goal.coverImageID {
                Text("Cover").font(Theme.Fonts.small).foregroundStyle(Theme.Palette.textTertiary).padding(.horizontal, Theme.Space.s)
            } else {
                Button("Set as Cover") { model.setCover(image, for: goal) }.buttonStyle(.ghost)
            }
            Button("Remove") { remove(image, at: index) }.buttonStyle(.ghost)
            IconButton(icon: .close, help: "Close (Esc)", action: close)
        }
    }

    private func sideButton(_ icon: IconName, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: Theme.Size.sidebarIcon)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Theme.GoalPanel.viewerButton, height: Theme.GoalPanel.viewerButton)
                .background(Circle().fill(Theme.Palette.elevated))
                .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: Theme.Size.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Theme.Opacity.disabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private func step(_ delta: Int) {
        guard let index else { return }
        let next = GalleryIndex.step(index, by: delta, count: images.count)
        guard next != index else { return }
        model.visionBoard.viewer = ImageViewerRequest(goalID: request.goalID, imageID: images[next].id)
    }

    private func remove(_ image: GoalImage, at index: Int) {
        let next = GalleryIndex.afterRemoving(at: index, count: images.count)
        let others = images.filter { $0.id != image.id }
        model.removeImage(image)
        if let next, others.indices.contains(next) {
            model.visionBoard.viewer = ImageViewerRequest(goalID: request.goalID, imageID: others[next].id)
        } else {
            close()
        }
    }

    private func close() {
        model.visionBoard.viewer = nil
        model.visionBoard.requestFocus()
    }
}
