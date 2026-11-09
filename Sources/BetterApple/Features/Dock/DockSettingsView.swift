import AppKit
import SwiftUI

struct DockSettingsView: View {
    @ObservedObject var manager: DockManager
    var body: some View {
        Form {
            Section("BetterApple Dock") {
                Toggle("Enable BetterApple Dock", isOn: $manager.preferences.enabled)
                Picker("Presentation", selection: $manager.preferences.presentation) {
                    ForEach(DockPresentation.allCases) { presentation in Text(presentation.title).tag(presentation) }
                }
                Text("This is an independent Dock alongside the macOS Dock. You can customize it while it is turned off; your setup is kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let service = manager.nativeDock { NativeDockSettingsView(service: service) }
            Section("Reference layouts") {
                HStack {
                    Button("Floating tiles") { manager.applyLayoutPreset(.floating) }
                    Button("Continuous rail") { manager.applyLayoutPreset(.rail) }
                }
                Text("Apply a modular layout with apps, music, timer, battery and a note. Your apps, note, display selection and on/off choice are preserved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Modules and order") {
                ForEach(Array(manager.preferences.moduleOrder.enumerated()), id: \.element) { index, module in
                    HStack {
                        Toggle(isOn: Binding(get: { manager.preferences.enabledModules.contains(module) },
                                             set: { manager.setModule(module, enabled: $0) })) {
                            Label(module.title, systemImage: module.symbol)
                        }
                        Button { manager.moveModule(module, by: -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0).accessibilityLabel("Move \(module.title) earlier")
                        Button { manager.moveModule(module, by: 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(index == manager.preferences.moduleOrder.count - 1).accessibilityLabel("Move \(module.title) later")
                    }.buttonStyle(.borderless)
                }
                Text("Each module is optional. Applications move as one block; reorder individual app icons in the Dock. Music connects only when you choose a player. Timer and note are shared across displays.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Placement") {
                Picker("Position", selection: $manager.preferences.position) { ForEach(DockPosition.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Show on every display", isOn: $manager.preferences.allDisplays)
                if !manager.preferences.allDisplays {
                    Picker("Display", selection: $manager.preferences.screenID) {
                        Text("Main display").tag("")
                        ForEach(NSScreen.screens, id: \.self) { screen in Text(screen.localizedName).tag(DockManager.screenID(screen)) }
                    }
                }
                if manager.preferences.allDisplays {
                    Text("Every display uses the same position, appearance and pinned applications.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Open macOS Dock settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!) }
            }
            Section("Behavior") {
                Toggle("Automatically hide", isOn: $manager.preferences.autoHide)
                Text("Move the pointer to the thin edge strip to reveal the Dock. It stays open while you interact with it.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show running applications", isOn: $manager.preferences.showRunningApplications)
                Text("Running apps appear after pinned apps. Use their context menu to keep them in the Dock.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Button("Use pure black · #000000") { manager.applyPureBlack() }
                Text("Pure black uses a solid, fully opaque black surface. Glass remains translucent; the display’s True Tone setting can affect how any color looks.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Theme", selection: $manager.preferences.theme) { ForEach(DockTheme.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Surface", selection: $manager.preferences.material) { ForEach(DockMaterial.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Accent color", selection: $manager.preferences.accent) { ForEach(DockAccent.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                slider("Icon size", value: $manager.preferences.iconSize, range: 24...80, step: 2)
                slider("Spacing", value: $manager.preferences.spacing, range: 0...24, step: 1)
                slider("Opacity", value: $manager.preferences.opacity, range: 0.2...1, step: 0.05, unit: "%")
                slider("Corner radius", value: $manager.preferences.cornerRadius, range: 0...40, step: 1)
                Toggle("Show app labels", isOn: $manager.preferences.showLabels)
            }
            Section("Motion") {
                slider("Magnification", value: $manager.preferences.magnification, range: 1...1.5, step: 0.02, unit: "×")
                slider("Animation duration", value: $manager.preferences.animationDuration, range: 0...0.5, step: 0.02, unit: "s")
                Text("Set magnification to 1× to disable it. Reduce Motion disables magnification and animated window resizing.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Pinned applications") {
                ForEach(manager.applications.filter { manager.preferences.applicationPaths.contains($0.id) }) { app in
                    HStack { Image(nsImage: app.icon).resizable().frame(width: 24, height: 24); Text(app.name); Spacer(); Button("Remove") { manager.remove(id: app.id) } }
                }
                Button("Add applications…") { manager.chooseApplications() }
                Text("When the BetterApple Dock is on, drag a pinned icon onto another to reorder. Missing applications are not shown in this list.").font(.caption).foregroundStyle(.secondary)
                if let error = manager.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("Quick note") {
                TextEditor(text: $manager.note).frame(height: 70).accessibilityLabel("Dock quick note")
                Text("Stored locally and shown in the Dock’s note tile. Turning the module off keeps your text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { manager.prepareSettings() }
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String = "pt") -> some View {
        let displayValue = unit == "%" ? value.wrappedValue.formatted(.percent.precision(.fractionLength(0))) : value.wrappedValue.formatted(.number.precision(.fractionLength(0...2))) + " " + unit
        return LabeledContent(title) {
            HStack {
                Text(displayValue).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)
                Slider(value: value, in: range, step: step).frame(width: 150).accessibilityLabel(title).accessibilityValue(displayValue)
            }
        }
    }
}
