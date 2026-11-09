import SwiftUI
import BetterAppleCore

extension WorkspaceAccent {
    var color: Color {
        switch self {
        case .mint: return .mint
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .rose: return .pink
        case .graphite: return .gray
        }
    }
}

extension SurfaceTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

struct IslandSurface: View {
    let appearance: IslandAppearance
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let base = scheme == .dark ? Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1) : Color(nsColor: .windowBackgroundColor)
        ZStack {
            if appearance.material == .glass && !reduceTransparency {
                shape.fill(.regularMaterial)
                shape.fill(base.opacity(appearance.opacity * 0.6))
            } else {
                shape.fill(base.opacity(reduceTransparency ? 1 : appearance.opacity))
            }
        }
        .overlay(shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.13), lineWidth: appearance.borderVisible ? 1 : 0))
    }
}
