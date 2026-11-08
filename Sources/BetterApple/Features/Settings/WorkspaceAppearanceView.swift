import SwiftUI
import BetterAppleCore

struct WorkspaceAppearanceView: View {
    @ObservedObject var model: AppModel
    let coordinator: AppCoordinator
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose a starting point, then make it yours.").foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(AppearancePreset.allCases.filter { $0 != .custom }) { preset in
                        Button { coordinator.applyPreset(preset) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: symbol(preset)).font(.title2).foregroundStyle(model.settings.island.visual.accent.color)
                                    Spacer()
                                    if model.settings.appearance == preset { Image(systemName: "checkmark.circle.fill").foregroundStyle(model.settings.island.visual.accent.color) }
                                }
                                Text(preset.title).font(.headline)
                                Text(description(preset)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(18).frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(model.settings.appearance == preset ? model.settings.island.visual.accent.color : Color.secondary.opacity(0.2), lineWidth: model.settings.appearance == preset ? 2 : 1))
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityLabel("Apply \(preset.title) preset")
                    }
                }
                Label(model.settings.appearance == .custom ? "Custom appearance" : "Current preset: \(model.settings.appearance.title)", systemImage: "slider.horizontal.3").font(.headline)
                Text("Presets adjust the Island and Dock appearance. Your applications, enabled modules, positions and widget content stay as configured. Fine-tune surfaces in Dynamic Island, Dock and Widgets.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Presets are applied immediately. You can export your complete configuration from General before trying a new look.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    private func symbol(_ preset: AppearancePreset) -> String {
        switch preset {
        case .default: return "circle.lefthalf.filled"
        case .minimal: return "minus"
        case .glass: return "square.on.square"
        case .compact: return "rectangle.compress.vertical"
        case .custom: return "slider.horizontal.3"
        }
    }
    private func description(_ preset: AppearancePreset) -> String {
        switch preset {
        case .default: return "Balanced spacing and a classic dark Island."
        case .minimal: return "A discreet indicator and smaller Dock icons."
        case .glass: return "Translucent materials that follow your Mac."
        case .compact: return "Tighter geometry for a focused workspace."
        case .custom: return "Your individual adjustments."
        }
    }
}
