import AppKit
import SwiftUI
import Combine
import BetterAppleCore

final class IslandPanel: NSPanel {
    var acceptsKeyboardFocus = false
    var isKeyboardTarget = false
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
}

final class CameraCapPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var selected: ModuleID = .calculator
    @Published var expandedContentVisible = false
    @Published var compactContentVisible = true
    @Published var focusRequest = 0
}

@MainActor
final class IslandManager {
    let state = IslandState()
    private let model: AppModel
    private let registry: IslandModuleRegistry
    private let sources: IslandActivitySources
    private var destinations: [(panel: IslandPanel, screen: NSScreen, cap: CameraCapPanel?)] = []
    private var observations: Set<AnyCancellable> = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var closeTask: Task<Void, Never>?
    private var contentTask: Task<Void, Never>?
    private var geometryTask: Task<Void, Never>?
    private var geometryDeadline: TimeInterval = 0
    private var generation = 0
    private var hoveredPanels = Set<ObjectIdentifier>()
    private var configuredDefault: ModuleID?
    private var configuredAllDisplays: Bool?
    private var configuredPlacement: IslandPlacement?
    private var stopped = false
    var onVisibilityChange: (() -> Void)?

    init(model: AppModel, registry: IslandModuleRegistry, sources: IslandActivitySources) {
        self.model = model; self.registry = registry; self.sources = sources
        state.selected = model.settings.island.defaultModule
        state.$expanded.removeDuplicates().dropFirst().sink { [weak self] expanded in
            Task { @MainActor in
                guard let self, self.state.expanded == expanded, !self.stopped else { return }
                self.transition(to: expanded)
            }
        }.store(in: &observations)
        state.$selected.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.onVisibilityChange?() }
        }.store(in: &observations)
        observe(NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.rebuild() }
        observe(NSWindow.didChangeOcclusionStateNotification) { [weak self] notification in
            guard let self, let window = notification.object as? IslandPanel,
                  self.destinations.contains(where: { $0.panel === window }) else { return }
            self.onVisibilityChange?()
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observe(name) { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow,
                      self.destinations.contains(where: { $0.panel === window || $0.panel === window.parent }) else { return }
                if name == NSWindow.didResignKeyNotification && self.destinations.contains(where: { $0.panel === window && $0.panel.isKeyboardTarget }) {
                    self.state.focusRequest = 0
                    self.destinations.forEach { $0.panel.isKeyboardTarget = false }
                }
                self.scheduleAutoClose()
            }
        }
        observe(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] _ in self?.applySettings() }
    }
    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        let center = name == NSWorkspace.accessibilityDisplayOptionsDidChangeNotification ? NSWorkspace.shared.notificationCenter : NotificationCenter.default
        notificationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        })
    }
    private var hasVisiblePanel: Bool {
        destinations.contains { $0.panel.isVisible && $0.panel.occlusionState.contains(.visible) }
    }
    var activeModule: ModuleID? { model.settings.island.enabled && state.expanded && hasVisiblePanel ? state.selected : nil }
    var compactModule: ModuleID? {
        let settings = model.settings.island
        return settings.placementMode == .floating && settings.enabled && !state.expanded && !settings.minimal && settings.visual.compactStatus && hasVisiblePanel ? state.selected : nil
    }
    func rebuild() {
        guard !stopped else { return }
        let restoreKeyboardFocus = destinations.contains { $0.panel.isKeyWindow }
        if !restoreKeyboardFocus { state.focusRequest = 0 }
        cancelPendingWork(); hoveredPanels.removeAll(); geometryDeadline = 0
        destinations.forEach { $0.cap?.orderOut(nil); $0.cap?.contentView = nil; $0.cap?.close(); $0.panel.orderOut(nil); $0.panel.contentView = nil; $0.panel.close() }; destinations.removeAll()
        let settings = model.settings.island
        configuredAllDisplays = settings.allDisplays
        configuredPlacement = settings.placementMode
        guard settings.enabled else { collapse(); settleContent(); onVisibilityChange?(); return }
        updateSelection()
        let preferred = settings.placementMode == .camera ? (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first) : NSScreen.screens.first
        let screens = settings.allDisplays ? NSScreen.screens : preferred.map { [$0] } ?? []
        guard !screens.isEmpty else { state.focusRequest = 0; settleContent(); onVisibilityChange?(); return }
        for screen in screens {
            let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.animationBehavior = .none; panel.level = .floating; panel.hidesOnDeactivate = false
            let hosting = NSHostingView(rootView: IslandView(model: model, state: state, registry: registry, sources: sources,
                pin: { [weak self] in self?.togglePin() },
                hover: { [weak self, weak panel] inside in if let panel { self?.handlePointer(inside, panel: panel) } },
                toggle: { [weak self] in self?.toggle() }, open: { [weak self] in self?.open() }, close: { [weak self] in self?.collapse() },
                select: { [weak self] in self?.selectModule($0) }, keyboardActive: { [weak panel] in panel?.isKeyboardTarget == true }))
            hosting.sizingOptions = []
            // AppKit owns panel geometry. A plain container prevents SwiftUI's
            // animated root-window sizing from competing with interrupted resizes.
            let container = NSView(frame: .zero)
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)
            panel.contentView = container
            var cap: CameraCapPanel?
            if settings.placementMode == .camera, let frame = cameraLayout(for: screen).capFrame {
                let trigger = CameraCapPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
                trigger.isReleasedWhenClosed = false; trigger.isOpaque = false; trigger.backgroundColor = .clear
                trigger.hasShadow = false; trigger.animationBehavior = .none; trigger.hidesOnDeactivate = false
                trigger.level = .statusBar
                let view = NSHostingView(rootView: CameraCapView(
                    hover: { [weak self, weak trigger] inside in if let trigger { self?.handlePointer(inside, panel: trigger) } },
                    expand: { [weak self] in self?.open() }))
                view.sizingOptions = []; trigger.contentView = view; cap = trigger
            }
            destinations.append((panel, screen, cap))
        }
        applySettings()
        destinations.forEach { $0.panel.orderFrontRegardless(); $0.cap?.orderFrontRegardless() }
        if restoreKeyboardFocus && state.expanded { requestKeyboardFocus() }
        onVisibilityChange?()
    }
    func toggle() {
        guard model.settings.island.enabled else { return }
        if state.expanded { collapse() }
        else { open() }
    }
    func open() {
        guard model.settings.island.enabled else { return }
        closeTask?.cancel(); closeTask = nil
        state.expanded = true
        requestKeyboardFocus()
    }
    func collapse() {
        closeTask?.cancel(); closeTask = nil
        state.pinned = false; state.focusRequest = 0; state.expanded = false
        relinquishKeyboardFocus()
    }
    func togglePin() {
        closeTask?.cancel(); closeTask = nil
        state.pinned.toggle()
        if state.pinned { state.expanded = true }
        else { scheduleAutoClose() }
    }
    func selectModule(_ module: ModuleID) {
        guard model.settings.island.modules.contains(module) else { return }
        state.selected = module; requestKeyboardFocus()
    }
    private func requestKeyboardFocus() {
        guard state.expanded else { return }
        let panel = destinations.first { $0.panel.frame.contains(NSEvent.mouseLocation) || $0.cap?.frame.contains(NSEvent.mouseLocation) == true }?.panel ?? destinations.first?.panel
        guard let panel, panel.isOnActiveSpace else { return }
        destinations.forEach { $0.panel.isKeyboardTarget = $0.panel === panel }
        panel.acceptsKeyboardFocus = true; panel.makeKeyAndOrderFront(nil)
        state.focusRequest = state.focusRequest == Int.max ? 1 : state.focusRequest + 1
    }
    func yieldKeyboardToSettings() {
        state.focusRequest = 0
        relinquishKeyboardFocus()
    }
    private func relinquishKeyboardFocus() {
        for (panel, _, _) in destinations {
            panel.isKeyboardTarget = false
            panel.acceptsKeyboardFocus = false
            if panel.isKeyWindow { panel.makeFirstResponder(nil); panel.resignKey() }
        }
    }
    private func updateSelection() {
        let settings = model.settings.island
        if configuredDefault != settings.defaultModule || !settings.modules.contains(state.selected) { state.selected = settings.defaultModule }
        configuredDefault = settings.defaultModule
    }
    /// Appearance edits preserve the actual window, module state and native editor.
    func applySettings() {
        guard !stopped else { return }
        cancelPendingWork()
        let settings = model.settings.island
        guard settings.enabled, !destinations.isEmpty, configuredAllDisplays == settings.allDisplays, configuredPlacement == settings.placementMode else { rebuild(); return }
        updateSelection()
        for (panel, _, _) in destinations {
            panel.hasShadow = settings.visual.shadowVisible && (state.expanded || settings.placementMode == .floating); panel.acceptsKeyboardFocus = state.expanded
            var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
            if settings.showInFullScreen { behavior.insert(.fullScreenAuxiliary) }
            if panel.collectionBehavior != behavior { panel.collectionBehavior = behavior }
        }
        for destination in destinations { destination.cap?.collectionBehavior = destination.panel.collectionBehavior }
        settleContent(); layout(duration: 0); onVisibilityChange?(); scheduleAutoClose()
    }
    private func settleContent() {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.expandedContentVisible = state.expanded; state.compactContentVisible = !state.expanded
        }
    }
    private func transition(to expanded: Bool) {
        contentTask?.cancel(); geometryTask?.cancel(); generation += 1
        let current = generation
        let plan = SurfaceMotionPlan.island(expanded: expanded, requestedDuration: model.settings.island.visual.animationDuration,
                                            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        destinations.forEach { $0.panel.acceptsKeyboardFocus = expanded }
        if !expanded { state.focusRequest = 0; relinquishKeyboardFocus() }
        if plan.windowDuration == 0 { settleContent(); layout(duration: 0); onVisibilityChange?(); return }
        withAnimation(WorkspaceMotion.animation(reduceMotion: false, duration: min(WorkspaceMotion.quick, plan.windowDuration))) {
            state.expandedContentVisible = false; state.compactContentVisible = false
        }
        layout(duration: plan.windowDuration)
        contentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(plan.revealDelay))
            guard !Task.isCancelled, let self, self.generation == current, self.state.expanded == expanded, !self.stopped else { return }
            withAnimation(WorkspaceMotion.animation(reduceMotion: false, duration: plan.contentDuration)) {
                self.state.expandedContentVisible = expanded; self.state.compactContentVisible = !expanded
            }
            self.contentTask = nil
        }
        onVisibilityChange?()
    }
    func handlePointer(_ inside: Bool, panel: NSWindow) {
        guard destinations.contains(where: { $0.panel === panel || $0.cap === panel }), !stopped else { return }
        if inside {
            hoveredPanels.insert(ObjectIdentifier(panel)); closeTask?.cancel(); closeTask = nil
            if model.settings.island.hoverToExpand && !state.expanded { state.focusRequest = 0; state.expanded = true }
        } else { hoveredPanels.remove(ObjectIdentifier(panel)); scheduleAutoClose() }
    }
    private func scheduleAutoClose() {
        closeTask?.cancel(); closeTask = nil
        let delay = model.settings.island.autoCloseDelay
        guard !stopped, state.expanded, !state.pinned, hoveredPanels.isEmpty, delay > 0 else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            self.closeTask = nil
            let editing = self.destinations.contains { entry in
                (entry.panel.isKeyWindow && (entry.panel.firstResponder as? NSTextView)?.isFieldEditor == true) || entry.panel.childWindows?.contains(where: \.isVisible) == true
            }
            let pointerInside = self.destinations.contains { ($0.panel.isVisible && $0.panel.isOnActiveSpace && $0.panel.frame.contains(NSEvent.mouseLocation)) || ($0.cap?.isVisible == true && $0.cap?.isOnActiveSpace == true && $0.cap?.frame.contains(NSEvent.mouseLocation) == true) }
            guard self.hoveredPanels.isEmpty, !pointerInside, !editing, !self.state.pinned, self.model.settings.island.autoCloseDelay > 0 else { return }
            self.collapse()
        }
    }
    private func cameraLayout(for screen: NSScreen) -> IslandWindowLayout {
        CameraIslandGeometry.layout(screen: CameraScreenMetrics(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top, auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea),
            expanded: state.expanded, expandedWidth: model.settings.island.expandedWidth, expandedHeight: model.settings.island.expandedHeight)
    }
    private func layout(duration: Double) {
        let settings = model.settings.island
        for (panel, screen, cap) in destinations {
            let available = screen.visibleFrame
            let top = max(available.minY, min(available.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 4)
            let size = NSSize(width: min(available.width, state.expanded ? settings.expandedWidth : settings.width),
                              height: min(max(0, top - available.minY), state.expanded ? settings.expandedHeight : (settings.minimal ? 12 : settings.height)))
            let rect: NSRect
            if settings.placementMode == .camera {
                let geometry = cameraLayout(for: screen)
                rect = geometry.bodyFrame
                if let frame = geometry.capFrame { cap?.setFrame(frame, display: true) }
            } else {
                rect = NSRect(x: min(available.maxX - size.width, max(available.minX, screen.frame.midX - size.width / 2 + settings.offsetX)),
                              y: max(available.minY, top - size.height - settings.offsetY), width: size.width, height: size.height)
            }
            panel.hasShadow = settings.visual.shadowVisible && (state.expanded || settings.placementMode == .floating)
            guard panel.frame != rect else { continue }
            if duration > 0 {
                geometryDeadline = max(geometryDeadline, ProcessInfo.processInfo.systemUptime + duration)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration; context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: state.expanded)
                    panel.animator().setFrame(rect, display: true)
                }
            } else { panel.setFrame(rect, display: true) }
        }
        settleGeometryAfterInterruption()
    }
    /// One finite reconciliation handles rapid reversals/pref edits; no display-link or idle timer.
    private func settleGeometryAfterInterruption() {
        geometryTask?.cancel(); geometryTask = nil
        let remaining = geometryDeadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { geometryDeadline = 0; return }
        let current = generation
        geometryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining + 0.02))
            guard !Task.isCancelled, let self, !self.stopped, self.generation == current else { return }
            self.geometryDeadline = 0; self.geometryTask = nil; self.layout(duration: 0)
        }
    }
    private func cancelPendingWork() {
        closeTask?.cancel(); closeTask = nil; contentTask?.cancel(); contentTask = nil
        geometryTask?.cancel(); geometryTask = nil; generation += 1
    }
    func stop() {
        stopped = true; cancelPendingWork(); relinquishKeyboardFocus()
        destinations.forEach { $0.cap?.orderOut(nil); $0.cap?.contentView = nil; $0.cap?.close(); $0.panel.orderOut(nil); $0.panel.contentView = nil; $0.panel.close() }; destinations.removeAll()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll(); observations.removeAll(); hoveredPanels.removeAll()
    }
}
