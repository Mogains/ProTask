import SwiftUI

#if DEBUG
/// Every timeline color as a dot, a bar and a soft fill, for checking the palette in both appearances.
struct TimelinePaletteSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(TimelineColor.allCases) { color in
                HStack(spacing: Theme.Space.m) {
                    Circle().fill(Theme.Vision.color(color))
                        .frame(width: Theme.Size.checkbox, height: Theme.Size.checkbox)
                    Text(color.title)
                        .font(Theme.Fonts.smallMedium)
                        .foregroundStyle(Theme.Vision.color(color))
                        .frame(width: Theme.Size.propertyLabel, alignment: .leading)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Vision.fill(color))
                        RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Vision.color(color))
                            .frame(width: Theme.Size.panelWidth / 2)
                    }
                    .frame(width: Theme.Size.panelWidth, height: Theme.Size.iconButton)
                    Text("Finish the garden studio")
                        .font(Theme.Fonts.small)
                        .foregroundStyle(Theme.Palette.text)
                        .padding(.horizontal, Theme.Space.s)
                        .frame(height: Theme.Size.iconButton)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Vision.fill(color)))
                }
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.Palette.background)
    }
}
#endif
