import AppKit
import SwiftUI

private struct DockIconFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct DockSurface: View {
    @ObservedObject var manager: DockManager
    let screenID: String
    @State private var pointer: CGPoint?
    @State private var iconFrames: [String: CGRect] = [:]
    @State private var targetedID: String?
    @FocusState private var focusedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var vertical: Bool { manager.preferences.position != .bottom }
    private var accent: Color { manager.preferences.accent.color }
    private var expanded: Bool { !manager.preferences.autoHide || manager.hoveringScreens.contains(screenID) }
    private var metrics: DockLayoutMetrics { DockLayoutMetrics(manager.preferences, reduceMotion: reduceMotion) }
    private var coordinateName: String { "dock-surface-" + screenID }
    private var revealOffset: CGSize {
        guard !expanded, !reduceMotion else { return .zero }
        switch manager.preferences.position {
        case .bottom: return CGSize(width: 0, height: 8)
        case .left: return CGSize(width: -8, height: 0)
        case .right: return CGSize(width: 8, height: 0)
        }
    }
    var body: some View {
        let offsets = displacements
        ZStack {
            Button { manager.hover(true, screenID: screenID) } label: {
                Capsule().fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Capsule().stroke(accent.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show BetterApple Dock")
            .opacity(expanded ? 0 : 1)
            .allowsHitTesting(!expanded)
            .accessibilityHidden(expanded)

            ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                let layout = vertical ? AnyLayout(VStackLayout(spacing: manager.preferences.spacing)) : AnyLayout(HStackLayout(spacing: manager.preferences.spacing))
                layout {
                    ForEach(manager.applications) { app in icon(app, displacement: offsets[app.id] ?? 0) }
                    if manager.applications.isEmpty {
                        Button { manager.chooseApplications() } label: {
                            Image(systemName: "plus.app").font(.title)
                                .frame(width: metrics.hitSide, height: metrics.hitSide)
                        }.buttonStyle(.plain).help("Add applications").accessibilityLabel("Add applications to Dock")
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding(vertical: vertical))
                .padding(.top, metrics.topPadding(vertical: vertical))
                .padding(.bottom, metrics.bottomPadding(vertical: vertical))
            }
            .background { background }
            .clipShape(RoundedRectangle(cornerRadius: manager.preferences.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: manager.preferences.cornerRadius).stroke(accent.opacity(0.23)))
            .opacity(expanded ? 1 : 0)
            .offset(revealOffset)
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .coordinateSpace(name: coordinateName)
        .contentShape(Rectangle())
        .preferredColorScheme(manager.preferences.theme.colorScheme)
        .tint(accent)
        .accentColor(accent)
        .onPreferenceChange(DockIconFrames.self) { iconFrames = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                guard expanded else { return }
                // Coalesce subpoint mouse motion without a timer or display link.
                if let pointer, hypot(pointer.x - point.x, pointer.y - point.y) < 0.75 { return }
                pointer = point
            case .ended: pointer = nil
            }
        }
        .onHover { inside in
            if !inside { pointer = nil }
            manager.hover(inside, screenID: screenID)
        }
        .onChange(of: expanded) { _, visible in if !visible { pointer = nil; targetedID = nil } }
        .onChange(of: manager.applications.map(\.id)) { _, ids in
            if let targetedID, !ids.contains(targetedID) { self.targetedID = nil }
        }
        .onChange(of: focusedID) { _, value in
            if value != nil { manager.hover(true, screenID: screenID) }
        }
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: manager.preferences.animationDuration), value: pointer)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: manager.preferences.animationDuration), value: expanded)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: manager.preferences.animationDuration), value: manager.applications.map(\.id))
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: targetedID)
    }
    @ViewBuilder private var background: some View {
        if manager.preferences.material == .glass && !reduceTransparency {
            Rectangle().fill(.ultraThinMaterial).opacity(manager.preferences.opacity)
        } else {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor)).opacity(reduceTransparency ? 1 : manager.preferences.opacity)
        }
    }
    private func magnification(for id: String) -> CGFloat {
        guard !reduceMotion, manager.preferences.magnification > 1, let pointer, let frame = iconFrames[id] else { return 1 }
        let distance = vertical ? abs(pointer.y - frame.midY) : abs(pointer.x - frame.midX)
        let reach = (metrics.hitSide + manager.preferences.spacing) * 1.65
        let influence = max(0, 1 - distance / reach)
        return 1 + (manager.preferences.magnification - 1) * influence * influence
    }
    /// Shift visible items within stable logical slots. Growing a large icon
    /// pushes its neighbors apart without changing the geometry that drives
    /// the pointer falloff, avoiding hover/layout feedback oscillation.
    private var displacements: [String: CGFloat] {
        let growths = manager.applications.map { manager.preferences.iconSize * (magnification(for: $0.id) - 1) }
        let excess = growths.map { growth in
            max(0, (vertical ? growth : manager.preferences.iconSize + growth - metrics.itemWidth) - manager.preferences.spacing)
        }
        let total = excess.reduce(0, +)
        var before: CGFloat = 0
        var result: [String: CGFloat] = [:]
        for (index, app) in manager.applications.enumerated() {
            let after = total - before - excess[index]
            result[app.id] = (before - after) / 2 + (vertical ? growths[index] / 2 : 0)
            before += excess[index]
        }
        return result
    }
    private func icon(_ app: DockApplication, displacement: CGFloat) -> some View {
        VStack(spacing: 3) {
            Button { manager.launch(app) } label: {
                Image(nsImage: app.icon).resizable().scaledToFit()
                    .frame(width: manager.preferences.iconSize, height: manager.preferences.iconSize)
                    .scaleEffect(magnification(for: app.id), anchor: .bottom)
                    .frame(width: metrics.hitSide, height: metrics.hitSide)
            }
            .buttonStyle(DockIconButtonStyle(reduceMotion: reduceMotion, duration: manager.preferences.animationDuration))
            .focused($focusedID, equals: app.id)
            .help(app.name).accessibilityLabel("Open \(app.name)")
            .accessibilityValue(app.running ? "Running" : "Not running")
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(focusedID == app.id ? accent : .clear, lineWidth: 2).padding(-3))
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
                defer { targetedID = nil }
                guard let source = items.first, manager.preferences.applicationPaths.contains(source), manager.preferences.applicationPaths.contains(app.id) else { return false }
                manager.move(from: source, to: app.id); return true
            } isTargeted: { active in
                if active && manager.preferences.applicationPaths.contains(app.id) { targetedID = app.id }
                else if targetedID == app.id { targetedID = nil }
            }
            Circle().fill(app.running ? accent : .clear).frame(width: 4, height: 4).accessibilityHidden(true)
            if manager.preferences.showLabels {
                Text(app.name).font(.system(size: 9, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .frame(width: metrics.itemWidth, height: 11).accessibilityHidden(true)
            }
        }
        .frame(width: metrics.itemWidth, height: metrics.itemHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(targetedID == app.id ? 0.16 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(targetedID == app.id ? 0.7 : 0), lineWidth: 1))
        .offset(x: vertical ? 0 : displacement, y: vertical ? displacement : 0)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: DockIconFrames.self, value: [app.id: proxy.frame(in: .named(coordinateName))])
        })
        .transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
    }
}

private struct DockIconButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    let duration: Double
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: min(WorkspaceMotion.quick, duration)), value: configuration.isPressed)
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
