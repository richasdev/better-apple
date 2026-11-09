import AppKit
import SwiftUI

struct DockTileBackground: View {
    let preferences: DockPreferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        RoundedRectangle(cornerRadius: min(22, preferences.cornerRadius))
            .fill(fill)
            .opacity(reduceTransparency ? 1 : preferences.opacity)
            .overlay(RoundedRectangle(cornerRadius: min(22, preferences.cornerRadius)).stroke(.primary.opacity(0.09)))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
    private var fill: AnyShapeStyle {
        if preferences.material == .glass && !reduceTransparency { return AnyShapeStyle(.ultraThinMaterial) }
        return AnyShapeStyle(colorScheme == .dark ? Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1) : Color(nsColor: .windowBackgroundColor))
    }
}
