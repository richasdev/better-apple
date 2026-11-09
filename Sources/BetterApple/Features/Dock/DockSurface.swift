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
    private var contentMetrics: DockContentMetrics {
        DockContentMetrics(manager.preferences, applicationCount: manager.applications.count, reduceMotion: reduceMotion)
    }
    @Environment(\.colorScheme) private var colorScheme
    private var effectiveScheme: ColorScheme {
        switch manager.preferences.theme {
        case .system: return colorScheme
        case .dark: return .dark
        case .light: return .light
        }
    }
    private var coordinateName: String { "dock-surface-" + screenID }
    private var motionOff: Bool { reduceMotion || manager.preferences.animationDuration == 0 }
    private var revealOffset: CGSize {
        guard !expanded, !reduceMotion else { return .zero }
        switch manager.preferences.position {
        case .bottom: return CGSize(width: 0, height: 8)
        case .left: return CGSize(width: -8, height: 0)
        case .right: return CGSize(width: 8, height: 0)
        }
    }
    var body: some View {
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
                    ForEach(contentMetrics.modules) { module in
                        if module == .apps {
                            appGroup
                        } else {
                            Group {
                                if expanded { DockModuleView(module: module, manager: manager) }
                                else { Color.clear.frame(width: module.tileWidth, height: DockModule.tileHeight) }
                            }
                            .background {
                                if manager.preferences.presentation == .floating {
                                    DockTileBackground(preferences: manager.preferences)
                                } else {
                                    RoundedRectangle(cornerRadius: min(16, manager.preferences.cornerRadius))
                                        .fill(manager.preferences.theme == .dark && manager.preferences.material == .solid && manager.preferences.opacity == 1 ? Color.black : Color.primary.opacity(0.035))
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(module.title)
                        }
                    }
                    if contentMetrics.modules.isEmpty {
                        Button("Add applications…") { manager.chooseApplications() }
                            .frame(width: 160, height: contentMetrics.crossContent)
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding(vertical: vertical))
                .padding(.top, metrics.topPadding(vertical: vertical))
                .padding(.bottom, metrics.bottomPadding(vertical: vertical))
            }
            .scrollContentBackground(.hidden)
            .background {
                if manager.preferences.presentation == .rail {
                    background.clipShape(RoundedRectangle(cornerRadius: manager.preferences.cornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: manager.preferences.cornerRadius).stroke(accent.opacity(0.23)))
                }
            }
            .opacity(expanded ? 1 : 0)
            .offset(revealOffset)
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .coordinateSpace(name: coordinateName)
        .contentShape(Rectangle())
        .environment(\.colorScheme, effectiveScheme)
        .foregroundStyle(effectiveScheme == .dark ? Color.white : Color.black)
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
        .onChange(of: expanded) { _, visible in if !visible { pointer = nil; targetedID = nil; focusedID = nil } }
        .onChange(of: manager.applications.map(\.id)) { _, ids in
            if let targetedID, !ids.contains(targetedID) { self.targetedID = nil }
        }
        .onChange(of: focusedID) { _, value in
            if value != nil { manager.hover(true, screenID: screenID) }
        }
        // Pointer motion is direct feedback: spring tracking, not the reveal duration.
        .animation(pointer == nil ? WorkspaceMotion.release(reduceMotion: motionOff) : WorkspaceMotion.tracking(reduceMotion: motionOff), value: pointer)
        // Leaving is faster than arriving.
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: manager.preferences.animationDuration * (expanded ? 1 : 0.75)), value: expanded)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: manager.preferences.animationDuration), value: manager.applications.map(\.id))
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: manager.preferences.animationDuration), value: contentMetrics.modules)
        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: targetedID)
    }
    private var appGroup: some View {
        let offsets = displacements
        let layout = vertical ? AnyLayout(VStackLayout(spacing: manager.preferences.spacing)) : AnyLayout(HStackLayout(spacing: manager.preferences.spacing))
        return layout {
            ForEach(manager.applications) { app in icon(app, displacement: offsets[app.id] ?? 0) }
            if manager.applications.isEmpty {
                Button { manager.chooseApplications() } label: {
                    Image(systemName: "plus.app").font(.title).frame(width: metrics.itemWidth, height: metrics.itemHeight)
                }.buttonStyle(.plain).accessibilityLabel("Add applications to Dock")
            }
        }
        .frame(width: vertical ? contentMetrics.crossContent : nil, height: vertical ? nil : contentMetrics.crossContent)
        .padding(vertical ? .vertical : .horizontal, contentMetrics.appPadding)
    }
    @ViewBuilder private var background: some View {
        if manager.preferences.material == .glass && !reduceTransparency {
            Rectangle().fill(.ultraThinMaterial).opacity(manager.preferences.opacity)
        } else {
            Rectangle().fill(effectiveScheme == .dark ? Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1) : Color(nsColor: .windowBackgroundColor)).opacity(reduceTransparency ? 1 : manager.preferences.opacity)
        }
    }
    private func magnification(for id: String) -> CGFloat {
        guard !reduceMotion, manager.preferences.magnification > 1, let pointer, let frame = iconFrames[id] else { return 1 }
        let distance = vertical ? pointer.y - frame.midY : pointer.x - frame.midX
        let reach = (metrics.hitSide + manager.preferences.spacing) * 1.9
        return 1 + (manager.preferences.magnification - 1) * DockMagnificationFalloff.influence(distance: distance, reach: reach)
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
            Circle().fill(app.running ? Color.primary.opacity(0.85) : .clear).frame(width: 4, height: 4).accessibilityHidden(true)
            if manager.preferences.showLabels {
                Text(app.name).font(.system(size: 9, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .frame(width: metrics.itemWidth, height: 11).accessibilityHidden(true)
            }
        }
        .frame(width: metrics.itemWidth, height: metrics.itemHeight)
        // No permanent plate: the native app icon is the tile. Drop-target
        // feedback exists only while a drag is over this slot.
        .background {
            if targetedID == app.id {
                RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.7), lineWidth: 1))
            }
        }
        .offset(x: vertical ? 0 : displacement, y: vertical ? displacement : 0)
        // Measured AFTER .offset on purpose: a background after a geometry effect
        // reports the un-offset layout slot (verified by probe), so displacement
        // never feeds back into the falloff it is computed from.
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

/// Raised-cosine bell: 1 at the pointer, 0 at `reach`, zero slope at both ends.
/// C1-continuous, so crossing an icon centre has no cusp (the former squared
/// linear falloff had a slope break at distance 0).
enum DockMagnificationFalloff {
    static func influence(distance: CGFloat, reach: CGFloat) -> CGFloat {
        guard reach > 0, distance.isFinite else { return 0 }
        let d = abs(distance)
        guard d < reach else { return 0 }
        return 0.5 + 0.5 * cos(.pi * d / reach)
    }
}
