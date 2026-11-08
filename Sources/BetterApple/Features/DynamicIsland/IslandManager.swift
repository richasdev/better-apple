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
    @Published var pinned = false
    @Published var selected: ModuleID = .calculator
}

@MainActor
final class IslandManager {
    let state = IslandState()
    private let model: AppModel
    private let registry: IslandModuleRegistry
    private let sources: IslandActivitySources
    // A new borderless panel at .zero can report the primary display before its
    // first layout. Preserve the intended screen rather than deriving it from
    // the window's current frame, which would stack secondary-display panels.
    private var destinations: [(panel: IslandPanel, screen: NSScreen)] = []
    private var observations: Set<AnyCancellable> = []
    private var closeTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var configuredDefault: ModuleID?
    private var configuredAllDisplays: Bool?
    var onVisibilityChange: (() -> Void)?
    init(model: AppModel, registry: IslandModuleRegistry, sources: IslandActivitySources) {
        self.model = model; self.registry = registry; self.sources = sources
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
        configuredAllDisplays = settings.allDisplays
        guard settings.enabled else { state.expanded = false; onVisibilityChange?(); return }
        if configuredDefault != settings.defaultModule || !settings.modules.contains(state.selected) {
            state.selected = settings.defaultModule
        }
        configuredDefault = settings.defaultModule
        let screens = settings.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .floating; panel.hasShadow = settings.visual.shadowVisible; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            if settings.showInFullScreen { panel.collectionBehavior.insert(.fullScreenAuxiliary) }
            panel.contentView = NSHostingView(rootView: IslandView(model: model, state: state, registry: registry, sources: sources, pin: { [weak self] in self?.togglePin() }, hover: { [weak self] in self?.hover($0) }, toggle: { [weak self] in self?.toggle() }))
            destinations.append((panel, screen))
        }
        layout(animated: false)
        destinations.forEach { $0.panel.orderFrontRegardless() }
        onVisibilityChange?()
    }
    func toggle() { closeTask?.cancel(); if state.expanded { collapse() } else { state.expanded = true } }
    func collapse() { closeTask?.cancel(); state.pinned = false; state.expanded = false }
    func togglePin() { closeTask?.cancel(); state.pinned.toggle(); if state.pinned { state.expanded = true } }

    /// Preference edits update existing windows, preserving focus and module state.
    func applySettings() {
        closeTask?.cancel(); closeTask = nil
        let settings = model.settings.island
        guard settings.enabled, !destinations.isEmpty, configuredAllDisplays == settings.allDisplays else { rebuild(); return }
        if configuredDefault != settings.defaultModule || !settings.modules.contains(state.selected) { state.selected = settings.defaultModule }
        configuredDefault = settings.defaultModule
        for (panel, _) in destinations {
            panel.hasShadow = settings.visual.shadowVisible
            var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
            if settings.showInFullScreen { behavior.insert(.fullScreenAuxiliary) }
            if panel.collectionBehavior != behavior { panel.collectionBehavior = behavior }
        }
        layout(animated: false); onVisibilityChange?()
    }

    var compactModule: ModuleID? {
        guard model.settings.island.enabled, !state.expanded, !model.settings.island.minimal, model.settings.island.visual.compactStatus,
              destinations.contains(where: { $0.panel.isVisible && $0.panel.occlusionState.contains(.visible) }) else { return nil }
        return state.selected
    }
    private func hover(_ inside: Bool) {
        closeTask?.cancel()
        closeTask = nil
        if inside {
            if model.settings.island.hoverToExpand { state.expanded = true }
        } else if !state.pinned && model.settings.island.autoCloseDelay > 0 {
            let delay = model.settings.island.autoCloseDelay
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.closeTask = nil
                let interacting = self.destinations.contains { entry in
                    (entry.panel.isKeyWindow && (entry.panel.firstResponder as? NSTextView)?.isFieldEditor == true) || entry.panel.childWindows?.contains(where: \.isVisible) == true
                }
                guard !interacting, !self.state.pinned else { return }
                self.state.expanded = false
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
            guard panel.frame != rect else { continue }
            if animated && !reduceMotion && settings.visual.animationDuration > 0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = settings.visual.animationDuration; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
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
