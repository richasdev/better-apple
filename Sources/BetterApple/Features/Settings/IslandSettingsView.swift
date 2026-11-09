import SwiftUI
import BetterAppleCore

struct IslandSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var systemScheme
    private var visual: IslandAppearance { model.settings.island.visual }
    private var cameraMode: Bool { model.settings.island.placementMode == .camera }
    private var previewVisual: IslandAppearance {
        var value = visual
        if cameraMode { value.theme = .dark; value.material = .solid; value.opacity = 1; value.borderVisible = false }
        return value
    }
    var body: some View {
        Form {
            Section("Position") {
                Picker("Placement", selection: $model.settings.island.placementMode) {
                    ForEach(IslandPlacement.allCases) { Text($0.title).tag($0) }
                }
                Text(cameraMode ? "On a MacBook, aligns with the physical camera cutout and leaves a 4 pt hover edge. On other displays, the closed notch fits entirely inside the top menu bar; hover opens the controls below it." : "A separate floating surface below the menu bar, with adjustable offsets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Displays") {
                Picker("Show Island on", selection: $model.settings.island.allDisplays) {
                    Text(cameraMode ? "Camera display (automatic)" : "Primary display").tag(false)
                    Text("Every connected display").tag(true)
                }
                Text(model.settings.island.allDisplays
                     ? "Each display gets an Island. Expansion and the selected module are shared; displays without a camera cutout draw the same notch silhouette."
                     : (cameraMode ? "Uses the first display with a camera cutout, even when an external monitor is primary. If none has a cutout, uses the primary display." : "Uses the primary display configured in macOS."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Allow over full-screen apps", isOn: $model.settings.island.showInFullScreen)
                Text("Full-screen participation is off by default. Spaces and full-screen behavior depend on macOS window management.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Live appearance") {
                HStack {
                    Spacer()
                    if cameraMode {
                        NotchCapShape(bottomRadius: 10).fill(.black)
                            .frame(width: 209, height: 37)
                            .accessibilityLabel("Top-attached notch with inward shoulders and rounded bottom corners")
                    } else {
                    Label("BetterApple", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(visual.accent.color)
                        .frame(width: 220, height: 42)
                        .background(IslandSurface(appearance: previewVisual, radius: min(visual.cornerRadius, 21)))
                        .environment(\.colorScheme, previewVisual.theme.colorScheme ?? systemScheme)
                    }
                    Spacer()
                }.padding(.vertical, 12).accessibilityLabel("Island appearance preview")
                if !cameraMode {
                    Picker("Theme", selection: $model.settings.island.visual.theme) {
                        ForEach(SurfaceTheme.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Material", selection: $model.settings.island.visual.material) {
                        ForEach(SurfaceMaterial.allCases) { Text($0.title).tag($0) }
                    }
                }
                Picker("Accent", selection: $model.settings.island.visual.accent) {
                    ForEach(WorkspaceAccent.allCases) { Label($0.title, systemImage: "circle.fill").foregroundStyle($0.color).tag($0) }
                }
                if !cameraMode {
                    slider("Surface opacity", value: $model.settings.island.visual.opacity, range: 0.5...1, format: .percent)
                    Toggle("Border", isOn: $model.settings.island.visual.borderVisible)
                }
                slider("Corner radius", value: $model.settings.island.visual.cornerRadius, range: 0...40)
                Toggle("Shadow", isOn: $model.settings.island.visual.shadowVisible)
                Toggle("Module names below icons", isOn: $model.settings.island.visual.showModuleLabels)
                if cameraMode { Text("Camera mode uses an opaque black surface to match the physical cutout. Your floating theme is kept for switching back.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Behavior") {
                Toggle("Enable Dynamic Island", isOn: $model.settings.island.enabled)
                Toggle("Expand on hover", isOn: $model.settings.island.hoverToExpand)
                Toggle("Open horizontal overview first", isOn: $model.settings.island.overviewOnHoverEnabled)
                Text("Music and calendar open together. Detailed tools remain in the Tools menu. Your detailed panel size is preserved.").font(.caption).foregroundStyle(.secondary)
                Toggle("Audio output and low battery notices", isOn: $model.settings.island.systemNoticesEnabled)
                Toggle("Bluetooth connection notices", isOn: $model.settings.island.connectionNotificationsEnabled)
                Text("Opt in to briefly show connected and disconnected devices, including AirPods, without scanning or pairing. macOS may request Bluetooth access. AirPods battery and BLE-only devices are not available through this passive connection API.")
                    .font(.caption).foregroundStyle(.secondary)
                if !cameraMode {
                    Toggle("Minimal appearance", isOn: $model.settings.island.minimal)
                    Toggle("Live compact status", isOn: $model.settings.island.visual.compactStatus)
                    Text("Live compact status keeps the selected service active while visible. Turn it off for the lowest idle activity.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("The camera edge shows artwork and playback status while an authorized player is connected. The horizontal overview updates enabled music and calendar modules only while visible.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                slider("Close delay · 0 keeps open", value: $model.settings.island.autoCloseDelay, range: 0...10, format: .seconds)
                slider("Animation duration", value: $model.settings.island.visual.animationDuration, range: 0...0.8, format: .seconds)
                Text("Pin the expanded Island to keep it open. Escape closes it. Reduce Motion and Reduce Transparency follow macOS Accessibility settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Geometry") {
                Toggle("Fit height to the active module", isOn: $model.settings.island.dynamicHeightEnabled)
                if !cameraMode {
                    slider("Compact width", value: $model.settings.island.width, range: 140...500)
                    slider("Compact height", value: $model.settings.island.height, range: 24...64)
                }
                slider("Expanded width", value: $model.settings.island.expandedWidth, range: 340...650)
                slider(model.settings.island.dynamicHeightEnabled ? "Maximum expanded height" : "Expanded height", value: $model.settings.island.expandedHeight, range: 240...600)
                if !cameraMode {
                    slider("Horizontal offset", value: $model.settings.island.offsetX, range: -500...500)
                    slider("Distance below menu bar", value: $model.settings.island.offsetY, range: 0...200)
                } else {
                    Text("Size and position follow the measured camera cutout. Other displays draw a matching notch at the top. Switch to Floating for manual positioning.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
