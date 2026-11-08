import AppKit
import SwiftUI
import Combine
import QuartzCore
import BetterAppleCore

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var selected: ModuleID = .calculator
}

@MainActor
final class IslandManager {
    let state = IslandState()
    private let model: AppModel
    private let registry: IslandModuleRegistry
    // A new borderless panel at .zero can report the primary display before its
    // first layout. Preserve the intended screen rather than deriving it from
    // the window's current frame, which would stack secondary-display panels.
    private var destinations: [(panel: IslandPanel, screen: NSScreen)] = []
    private var observations: Set<AnyCancellable> = []
    private var closeTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var configuredDefault: ModuleID?
    var onVisibilityChange: (() -> Void)?
    init(model: AppModel, registry: IslandModuleRegistry) {
        self.model = model; self.registry = registry
        state.selected = model.settings.island.defaultModule
        state.$expanded.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.layout(animated: true); self?.onVisibilityChange?() }
        }.store(in: &observations)
        state.$selected.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.onVisibilityChange?() }
        }.store(in: &observations)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] notification in
            guard let panel = notification.object as? IslandPanel else { return }
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel, self.destinations.contains(where: { $0.panel === panel }) else { return }
                self.onVisibilityChange?()
            }
        }
    }
    var activeModule: ModuleID? {
        guard model.settings.island.enabled, state.expanded,
              destinations.contains(where: { $0.panel.isVisible && $0.panel.occlusionState.contains(.visible) }) else { return nil }
        return state.selected
    }
    func rebuild() {
        closeTask?.cancel()
        destinations.forEach { $0.panel.orderOut(nil); $0.panel.contentView = nil; $0.panel.close() }; destinations.removeAll()
        let settings = model.settings.island
        guard settings.enabled else { state.expanded = false; onVisibilityChange?(); return }
        if configuredDefault != settings.defaultModule || !settings.modules.contains(state.selected) {
            state.selected = settings.defaultModule
        }
        configuredDefault = settings.defaultModule
        let screens = settings.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .floating; panel.hasShadow = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            if settings.showInFullScreen { panel.collectionBehavior.insert(.fullScreenAuxiliary) }
            panel.contentView = NSHostingView(rootView: IslandView(model: model, state: state, registry: registry, hover: { [weak self] in self?.hover($0) }, toggle: { [weak self] in self?.toggle() }))
            destinations.append((panel, screen))
        }
        layout(animated: false)
        destinations.forEach { $0.panel.orderFrontRegardless() }
        onVisibilityChange?()
    }
    func toggle() { closeTask?.cancel(); state.expanded.toggle() }
    func collapse() { closeTask?.cancel(); state.expanded = false }
    private func hover(_ inside: Bool) {
        closeTask?.cancel()
        closeTask = nil
        if inside {
            if model.settings.island.hoverToExpand { state.expanded = true }
        } else if model.settings.island.autoCloseDelay > 0 {
            let delay = model.settings.island.autoCloseDelay
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.state.expanded = false
                self?.closeTask = nil
            }
        }
    }
    private func layout(animated: Bool) {
        let settings = model.settings.island
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (panel, screen) in destinations {
            // Stay below menu-bar / camera safe area rather than covering menu commands.
            let available = screen.visibleFrame
            let top = max(available.minY, min(available.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 4)
            let size = NSSize(width: min(available.width, state.expanded ? settings.expandedWidth : settings.width),
                              height: min(max(0, top - available.minY), state.expanded ? settings.expandedHeight : (settings.minimal ? 12 : settings.height)))
            let x = min(available.maxX - size.width, max(available.minX, screen.frame.midX - size.width / 2 + settings.offsetX))
            let y = max(available.minY, top - size.height - settings.offsetY)
            let rect = NSRect(origin: NSPoint(x: x, y: y), size: size)
            if animated && !reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.24; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(rect, display: true)
                }
            } else { panel.setFrame(rect, display: true) }
        }
    }
    func stop() {
        closeTask?.cancel(); destinations.forEach { $0.panel.orderOut(nil); $0.panel.contentView = nil; $0.panel.close() }; destinations.removeAll()
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer); screenObserver = nil }
        if let observer = occlusionObserver { NotificationCenter.default.removeObserver(observer); occlusionObserver = nil }
        observations.removeAll()
    }
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: IslandState
    let registry: IslandModuleRegistry
    let hover: (Bool) -> Void
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            if state.expanded {
                HStack {
                    Label("BetterApple", systemImage: "circle.lefthalf.filled").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: toggle) { Image(systemName: "chevron.up") }.buttonStyle(.plain).help("Collapse")
                }.padding(.bottom, 14)
                HStack(spacing: 6) {
                    ForEach(model.settings.island.modules) { module in
                        Button { state.selected = module } label: {
                            Image(systemName: module.symbol).font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity).frame(height: 30)
                                .background(state.selected == module ? Color.white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).help(module.title).accessibilityLabel(module.title)
                            .accessibilityAddTraits(state.selected == module ? .isSelected : [])
                    }
                }.padding(.bottom, 18)
                registry.content(for: state.selected).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if model.settings.island.minimal {
                Capsule().fill(.mint).frame(width: 28, height: 3)
            } else {
                HStack {
                    Image(systemName: state.selected.symbol).foregroundStyle(.mint)
                    Spacer()
                    Text("BetterApple").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }.contentShape(Rectangle()).onTapGesture(perform: toggle)
            }
        }
        .padding(state.expanded ? 20 : (model.settings.island.minimal ? 2 : 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.97), in: RoundedRectangle(cornerRadius: state.expanded ? 26 : 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: state.expanded ? 26 : 16).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .preferredColorScheme(.dark)
        .onHover(perform: hover)
        .onTapGesture { if !state.expanded { toggle() } }
        .onExitCommand { state.expanded = false }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.expanded)
    }
}
