import SwiftUI

/// ProTask's own icon set: hand-drawn 16x16 SVGs (scripts/make-icons.py) stored as template
/// images in Assets.xcassets/Icons, so they tint with `foregroundStyle`.
enum IconName: String, CaseIterable {
    case today, haveTo = "have-to", niceTo = "nice-to", parking, calendar, done, settings
    case sidebar, search, add, autoSort = "auto-sort", manual, panel, quickAdd = "quick-add", more, delete, send, later, close
    case `repeat`, drag, due, priority1 = "priority-1", priority2 = "priority-2", priority3 = "priority-3", notes, idea
    case mark

    var assetName: String { "icon-\(rawValue)" }
}

struct Icon: View {
    let name: IconName
    var size: CGFloat = Theme.Size.icon

    init(_ name: IconName, size: CGFloat = Theme.Size.icon) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name.assetName)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if DEBUG
/// Every icon at row and sidebar size, for comparing visual weight side by side.
struct IconSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ForEach([Theme.Size.icon, Theme.Size.sidebarIcon, Theme.Size.icon * 3], id: \.self) { size in
                HStack(spacing: Theme.Space.m) {
                    ForEach(IconName.allCases, id: \.self) { name in
                        VStack(spacing: Theme.Space.xs) {
                            Icon(name, size: size)
                            if size > Theme.Size.sidebarIcon {
                                Text(name.rawValue).font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(Theme.Palette.textSecondary)
        .padding(Theme.Space.l)
        .background(Theme.Palette.background)
    }
}
#endif
