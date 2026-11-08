import AppKit
import SwiftUI

struct DockSurface: View {
    @ObservedObject var manager: DockManager
    let screenID: String
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var vertical: Bool { manager.preferences.position != .bottom }
    private var accent: Color { manager.preferences.accent.color }
    private var expanded: Bool { !manager.preferences.autoHide || manager.hoveringScreens.contains(screenID) }
    var body: some View {
        Group {
            if !expanded {
                Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(accent.opacity(0.45)))
            } else {
                ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                    let layout = vertical ? AnyLayout(VStackLayout(spacing: manager.preferences.spacing)) : AnyLayout(HStackLayout(spacing: manager.preferences.spacing))
                    layout {
                        ForEach(manager.applications) { app in icon(app) }
                        if manager.applications.isEmpty {
                            Button { manager.chooseApplications() } label: { Image(systemName: "plus.app").font(.title) }.buttonStyle(.plain).help("Add applications")
                        }
                    }.padding(max(14, manager.preferences.iconSize * (manager.preferences.magnification - 1) / 2 + 8))
                }
                .background { background }
                .clipShape(RoundedRectangle(cornerRadius: manager.preferences.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: manager.preferences.cornerRadius).stroke(accent.opacity(0.23)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .preferredColorScheme(manager.preferences.theme.colorScheme)
        .tint(accent)
        .onHover { manager.hover($0, screenID: screenID) }
        .animation(reduceMotion || manager.preferences.animationDuration == 0 ? nil : .easeOut(duration: manager.preferences.animationDuration), value: hovered)
    }
    @ViewBuilder private var background: some View {
        if manager.preferences.material == .glass && !reduceTransparency {
            Rectangle().fill(.ultraThinMaterial).opacity(manager.preferences.opacity)
        } else {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor)).opacity(reduceTransparency ? 1 : manager.preferences.opacity)
        }
    }
    private func icon(_ app: DockApplication) -> some View {
        VStack(spacing: 3) {
            Button { manager.launch(app) } label: {
                Image(nsImage: app.icon).resizable().scaledToFit()
                    .frame(width: manager.preferences.iconSize, height: manager.preferences.iconSize)
                    .scaleEffect(hovered == app.id && !reduceMotion ? manager.preferences.magnification : 1)
            }
            .buttonStyle(.plain).help(app.name).accessibilityLabel("Open \(app.name)")
            .onHover { hovered = $0 ? app.id : nil }
            .contextMenu {
                Button("Open \(app.name)") { manager.launch(app) }
                Button("Show in Finder") { manager.reveal(app) }
                if manager.preferences.applicationPaths.contains(app.id) {
                    Button("Remove from BetterApple Dock") { manager.remove(id: app.id) }
                } else { Button("Keep in BetterApple Dock") { manager.pin(app) } }
                if app.running {
                    Divider()
                    Button("Quit \(app.name)") { manager.quit(app) }.disabled(!manager.canQuit(app))
                }
            }
            .draggable(app.id)
            .dropDestination(for: String.self) { items, _ in
                guard let source = items.first, manager.preferences.applicationPaths.contains(source), manager.preferences.applicationPaths.contains(app.id) else { return false }
                manager.move(from: source, to: app.id); return true
            }
            Circle().fill(app.running ? accent : .clear).frame(width: 4, height: 4).accessibilityHidden(true)
            if manager.preferences.showLabels {
                Text(app.name).font(.system(size: 9, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .frame(width: manager.preferences.iconSize + 12).accessibilityHidden(true)
            }
        }
    }
}

struct DockSettingsView: View {
    @ObservedObject var manager: DockManager
    var body: some View {
        Form {
            Section("Independent Dock") {
                Toggle("Enable BetterApple Dock", isOn: $manager.preferences.enabled)
                Picker("Position", selection: $manager.preferences.position) { ForEach(DockPosition.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Show on every display", isOn: $manager.preferences.allDisplays)
                if !manager.preferences.allDisplays {
                    Picker("Display", selection: $manager.preferences.screenID) {
                        Text("Main display").tag("")
                        ForEach(NSScreen.screens, id: \.self) { screen in Text(screen.localizedName).tag(DockManager.screenID(screen)) }
                    }
                }
                Toggle("Automatically hide", isOn: $manager.preferences.autoHide)
                Toggle("Show running applications", isOn: $manager.preferences.showRunningApplications)
                Text("Running apps appear after pinned apps. Use their context menu to keep them in the Dock.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $manager.preferences.theme) { ForEach(DockTheme.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Surface", selection: $manager.preferences.material) { ForEach(DockMaterial.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Accent color", selection: $manager.preferences.accent) { ForEach(DockAccent.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                slider("Icon size", value: $manager.preferences.iconSize, range: 24...80, step: 2)
                slider("Spacing", value: $manager.preferences.spacing, range: 0...24, step: 1)
                slider("Opacity", value: $manager.preferences.opacity, range: 0.2...1, step: 0.05)
                slider("Corner radius", value: $manager.preferences.cornerRadius, range: 0...40, step: 1)
                Toggle("Show app labels", isOn: $manager.preferences.showLabels)
            }
            Section("Motion") {
                slider("Magnification", value: $manager.preferences.magnification, range: 1...1.5, step: 0.02)
                slider("Animation duration", value: $manager.preferences.animationDuration, range: 0...0.5, step: 0.02)
                Text("Set magnification to 1× to disable it. Reduce Motion disables magnification and animated window resizing.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Pinned applications") {
                ForEach(manager.applications.filter { manager.preferences.applicationPaths.contains($0.id) }) { app in
                    HStack { Image(nsImage: app.icon).resizable().frame(width: 24, height: 24); Text(app.name); Spacer(); Button("Remove") { manager.remove(id: app.id) } }
                }
                Button("Add applications…") { manager.chooseApplications() }
                Text("Drag pinned icons onto another pinned icon to reorder. The macOS Dock remains independent.").font(.caption).foregroundStyle(.secondary)
                Button("Open macOS Dock settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!) }
                if let error = manager.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }.formStyle(.grouped)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            HStack {
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...2)))).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 42)
                Slider(value: value, in: range, step: step).frame(width: 150).accessibilityLabel(title)
            }
        }
    }
}
