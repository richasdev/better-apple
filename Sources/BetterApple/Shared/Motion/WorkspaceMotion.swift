import SwiftUI
import QuartzCore

enum WorkspaceMotion {
    static let quick = 0.12
    static let standard = 0.22
    static let content = 0.18
    static let settle = 0.28

    static func animation(reduceMotion: Bool, duration: Double = standard) -> Animation? {
        guard !reduceMotion, duration.isFinite, duration > 0 else { return nil }
        return .timingCurve(0.2, 0, 0, 1, duration: min(0.8, duration))
    }
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(y: 4))
    }
    static func windowTimingFunction(expanding: Bool) -> CAMediaTimingFunction {
        expanding ? CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            : CAMediaTimingFunction(controlPoints: 0.3, 0, 0.8, 1)
    }
}

private struct IslandFocusRequestKey: EnvironmentKey {
    static let defaultValue = 0
}
private struct WorkspaceMotionDisabledKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var workspaceMotionDisabled: Bool {
        get { self[WorkspaceMotionDisabledKey.self] }
        set { self[WorkspaceMotionDisabledKey.self] = newValue }
    }
    var islandFocusRequest: Int {
        get { self[IslandFocusRequestKey.self] }
        set { self[IslandFocusRequestKey.self] = newValue }
    }
}

/// A finite hover/press response for compact controls. Native text fields, toggles,
/// pickers and destructive confirmation controls retain their platform behavior.
struct SurfaceButtonStyle: ButtonStyle {
    var accent: Color = .accentColor
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        SurfaceButtonBody(configuration: configuration, accent: accent, prominent: prominent)
    }
}

private struct SurfaceButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let accent: Color
    let prominent: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceMotionDisabled) private var localMotionDisabled
    private var reduceMotion: Bool { systemReduceMotion || localMotionDisabled }
    var body: some View {
        configuration.label
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(minWidth: 28, minHeight: 28)
            .background(accent.opacity(enabled ? (configuration.isPressed ? 0.22 : hovered ? 0.12 : prominent ? 0.16 : 0) : 0), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(focused && enabled ? 0.8 : 0), lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: hovered)
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: configuration.isPressed)
    }
}
