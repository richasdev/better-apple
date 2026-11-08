import SwiftUI
import BetterAppleCore

struct IslandSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var systemScheme
    private var visual: IslandAppearance { model.settings.island.visual }
    var body: some View {
        Form {
            Section("Live appearance") {
                HStack {
                    Spacer()
                    Label("BetterApple", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(visual.accent.color)
                        .frame(width: 220, height: 42)
                        .background(IslandSurface(appearance: visual, radius: min(visual.cornerRadius, 21)))
                        .environment(\.colorScheme, visual.theme.colorScheme ?? systemScheme)
                    Spacer()
                }.padding(.vertical, 12).accessibilityLabel("Island appearance preview")
                Picker("Theme", selection: $model.settings.island.visual.theme) {
                    ForEach(SurfaceTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("Material", selection: $model.settings.island.visual.material) {
                    ForEach(SurfaceMaterial.allCases) { Text($0.title).tag($0) }
                }
                Picker("Accent", selection: $model.settings.island.visual.accent) {
                    ForEach(WorkspaceAccent.allCases) { Label($0.title, systemImage: "circle.fill").foregroundStyle($0.color).tag($0) }
                }
                slider("Surface opacity", value: $model.settings.island.visual.opacity, range: 0.5...1, format: .percent)
                slider("Corner radius", value: $model.settings.island.visual.cornerRadius, range: 0...40)
                Toggle("Border", isOn: $model.settings.island.visual.borderVisible)
                Toggle("Shadow", isOn: $model.settings.island.visual.shadowVisible)
                Toggle("Module names below icons", isOn: $model.settings.island.visual.showModuleLabels)
            }
            Section("Behavior") {
                Toggle("Enable Dynamic Island", isOn: $model.settings.island.enabled)
                Toggle("Expand on hover", isOn: $model.settings.island.hoverToExpand)
                Toggle("Minimal appearance", isOn: $model.settings.island.minimal)
                Toggle("Live compact status", isOn: $model.settings.island.visual.compactStatus)
                Text("Live compact status shows the selected module’s available data and keeps only that service active while the Island is visible. Turn it off for the lowest idle activity.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show on every display", isOn: $model.settings.island.allDisplays)
                Toggle("Allow over full-screen apps", isOn: $model.settings.island.showInFullScreen)
                slider("Close delay · 0 keeps open", value: $model.settings.island.autoCloseDelay, range: 0...10, format: .seconds)
                slider("Animation duration", value: $model.settings.island.visual.animationDuration, range: 0...0.8, format: .seconds)
                Text("Pin the expanded Island to keep it open. Escape closes it. Reduce Motion and Reduce Transparency follow macOS Accessibility settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Geometry") {
                slider("Compact width", value: $model.settings.island.width, range: 140...500)
                slider("Compact height", value: $model.settings.island.height, range: 24...64)
                slider("Expanded width", value: $model.settings.island.expandedWidth, range: 340...650)
                slider("Expanded height", value: $model.settings.island.expandedHeight, range: 240...600)
                slider("Horizontal offset", value: $model.settings.island.offsetX, range: -500...500)
                slider("Distance below menu bar", value: $model.settings.island.offsetY, range: 0...200)
            }
            Section("Enabled modules") {
                ForEach(ModuleID.allCases) { module in
                    Toggle(module.title, isOn: Binding(get: { model.settings.island.modules.contains(module) }, set: { enabled in
                        if enabled && !model.settings.island.modules.contains(module) { model.settings.island.modules.append(module) }
                        else if !enabled && model.settings.island.modules.count > 1 { model.settings.island.modules.removeAll { $0 == module } }
                        if !model.settings.island.modules.contains(model.settings.island.defaultModule) { model.settings.island.defaultModule = model.settings.island.modules[0] }
                    }))
                }
            }
            Section("Order and default") {
                ForEach(Array(model.settings.island.modules.enumerated()), id: \.element) { index, module in
                    HStack {
                        Label(module.title, systemImage: module.symbol); Spacer()
                        Button { model.settings.island.modules.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move up")
                        Button { model.settings.island.modules.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }.disabled(index == model.settings.island.modules.count - 1).help("Move down")
                    }
                }
                Picker("Default module", selection: $model.settings.island.defaultModule) { ForEach(model.settings.island.modules) { Text($0.title).tag($0) } }
            }
        }.formStyle(.grouped)
    }
    private enum ValueFormat { case points, seconds, percent }
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: ValueFormat = .points) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label); Spacer()
                Group {
                    switch format {
                    case .points: Text("\(Int(value.wrappedValue)) pt")
                    case .seconds: Text("\(value.wrappedValue, specifier: "%.2f") s")
                    case .percent: Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    }
                }.monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).accessibilityLabel(label)
        }
    }
}
