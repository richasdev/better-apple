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
final class IslandManager {
    let state = IslandState()
    private let model: AppModel
    private let registry: IslandModuleRegistry
    private let sources: IslandActivitySources
    private var destinations: [(panel: IslandPanel, screen: NSScreen, cap: CameraCapPanel?)] = []
    private var observations: Set<AnyCancellable> = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var closeTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    /// True only while a hover-opened overview is the sole reason the notch is open.
    private var revealedByHover = false
    private var contentTask: Task<Void, Never>?
    private var geometryTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
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
            Task { @MainActor in
                guard let self else { return }
                if self.state.expanded { self.layout(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : min(WorkspaceMotion.content, self.model.settings.island.visual.animationDuration)) }
                self.onVisibilityChange?()
            }
        }.store(in: &observations)
        sources.music.$isConnected.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in
                self?.updateCompactMusic()
                guard let self, self.state.expanded, self.state.selected == .music else { return }
                self.layout(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : min(WorkspaceMotion.content, self.model.settings.island.visual.animationDuration))
            }
        }.store(in: &observations)
        sources.music.$track.sink { [weak self] _ in
            Task { @MainActor in self?.updateCompactMusic() }
        }.store(in: &observations)
        sources.music.$artwork.sink { [weak self] _ in
            Task { @MainActor in self?.updateCompactMusic() }
        }.store(in: &observations)
        observe(NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.rebuild() }
        observe(NSWindow.didChangeOcclusionStateNotification) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow,
                  self.destinations.contains(where: { $0.panel === window || $0.cap === window }) else { return }
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
        // A close deadline that fell inside menu tracking was deferred; rearm it
        // once the Tools/player menu is dismissed.
        observe(NSMenu.didEndTrackingNotification) { [weak self] _ in
            guard let self, self.state.expanded else { return }
            self.scheduleAutoClose()
        }
        for name in [NSText.didChangeNotification, NSText.didEndEditingNotification,
                     NSControl.textDidChangeNotification, NSControl.textDidEndEditingNotification] {
            observe(name) { [weak self] notification in
                guard let self, self.state.expanded, let view = notification.object as? NSView,
                      self.destinations.contains(where: { $0.panel === view.window }) else { return }
                // Typing resets the exit deadline; committing marked input must
                // rearm it after the IME protection has ended.
                self.scheduleAutoClose()
            }
        }
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
    var activeModule: ModuleID? { model.settings.island.enabled && state.expanded && !state.overview && !state.connectionNoticeCompact && hasVisiblePanel ? state.selected : nil }
    var overviewModules: Set<ModuleID> {
        guard model.settings.island.enabled, state.expanded, state.overview, !state.connectionNoticeCompact, hasVisiblePanel else { return [] }
        return Set(model.settings.island.modules).intersection([.music, .calendar])
    }
    var compactMusicVisible: Bool {
        model.settings.island.enabled && !state.expanded && state.compactMusicTitle != nil && destinations.contains { $0.cap?.isVisible == true && $0.cap?.occlusionState.contains(.visible) == true }
    }
    private func updateCompactMusic() {
        guard !stopped else { return }
        let music = sources.music
        let track = model.settings.island.modules.contains(.music) && music.isConnected ? music.track : nil
        let hadWings = state.compactMusicTitle != nil
        if state.compactMusicTitle != track?.title { state.compactMusicTitle = track?.title }
        if state.compactMusicPlaying != (track?.isPlaying == true) { state.compactMusicPlaying = track?.isPlaying == true }
        let image = track == nil ? nil : music.artwork
        if state.compactArtwork !== image { state.compactArtwork = image }
        if hadWings != (track != nil), !state.expanded, !stopped {
            layout(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : min(WorkspaceMotion.content, model.settings.island.visual.animationDuration))
            onVisibilityChange?()
        }
    }
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
                toggle: { [weak self] in self?.toggle() }, open: { [weak self] in self?.reveal() }, close: { [weak self] in self?.collapse() },
                select: { [weak self] in self?.selectModule($0) }, overview: { [weak self] in self?.showOverview() }, keyboardActive: { [weak panel] in panel?.isKeyboardTarget == true }))
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
                let collapsed = cameraLayout(for: screen, expanded: false)
                let view = NSHostingView(rootView: CameraCapView(state: state, cameraWidth: collapsed.cameraWidth,
                    collapsedInset: CameraIslandGeometry.collapsedDrawnInset(collapsed),
                    hover: { [weak self, weak trigger] inside in if let trigger { self?.handlePointer(inside, panel: trigger) } },
                    expand: { [weak self] in self?.reveal() }))
                view.sizingOptions = []
                let container = NSView(frame: .zero)
                view.autoresizingMask = [.width, .height]
                container.addSubview(view)
                trigger.contentView = container; cap = trigger
            }
            destinations.append((panel, screen, cap))
        }
        applySettings()
        destinations.forEach { $0.panel.orderFrontRegardless(); $0.cap?.orderFrontRegardless() }
        if restoreKeyboardFocus && state.expanded && !state.overview { requestKeyboardFocus() }
        onVisibilityChange?()
    }
    func toggle() {
        guard model.settings.island.enabled else { return }
        if state.expanded { collapse() }
        else { reveal() }
    }
    func reveal() {
        if model.settings.island.overviewOnHoverEnabled { showOverview() } else { open() }
    }
    func showOverview() {
        guard model.settings.island.enabled else { return }
        let wasExpanded = state.expanded
        closeTask?.cancel(); closeTask = nil; cancelHoverOpen(); revealedByHover = false
        dismissConnectionNotice(collapseAutomatic: false)
        state.overview = true; state.focusRequest = 0
        relinquishKeyboardFocus()
        state.expanded = true
        if wasExpanded { transition(to: true) }
        onVisibilityChange?()
    }
    func open() {
        guard model.settings.island.enabled else { return }
        closeTask?.cancel(); closeTask = nil; cancelHoverOpen(); revealedByHover = false
        dismissConnectionNotice(collapseAutomatic: false)
        let switching = state.overview && state.expanded
        state.overview = false; state.expanded = true
        if switching { transition(to: true) }
        requestKeyboardFocus()
    }
    func collapse() {
        connectionTask?.cancel(); connectionTask = nil
        state.connectionNotice = nil; state.connectionNoticeCompact = false
        closeTask?.cancel(); closeTask = nil; cancelHoverOpen(); revealedByHover = false
        state.pinned = false; state.focusRequest = 0; state.expanded = false
        relinquishKeyboardFocus()
    }
    func presentConnection(name: String, symbol: String, connected: Bool, detail: String? = nil, percentage: Int? = nil, systemEvent: Bool = false) {
        guard !stopped, model.settings.island.enabled,
              systemEvent ? model.settings.island.systemNoticesEnabled : model.settings.island.connectionNotificationsEnabled else { return }
        connectionTask?.cancel(); closeTask?.cancel(); closeTask = nil
        state.connectionNoticeCompact = !state.expanded || state.connectionNoticeCompact
        state.connectionNotice = IslandConnectionNotice(name: String(name.prefix(120)), symbol: symbol, connected: connected, detail: detail, percentage: percentage, systemEvent: systemEvent)
        if !state.expanded { state.focusRequest = 0; state.expanded = true }
        else if state.connectionNoticeCompact { transition(to: true) }
        else { layout(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : min(WorkspaceMotion.content, model.settings.island.visual.animationDuration)) }
        connectionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            self.dismissConnectionNotice(collapseAutomatic: true)
        }
    }
    private func dismissConnectionNotice(collapseAutomatic: Bool) {
        guard state.connectionNotice != nil else { return }
        connectionTask?.cancel(); connectionTask = nil
        let compact = state.connectionNoticeCompact
        state.connectionNotice = nil; state.connectionNoticeCompact = false
        if compact && collapseAutomatic && !state.pinned && hoveredPanels.isEmpty { collapse() }
        else if compact { transition(to: state.expanded) }
        else if state.expanded { layout(duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : min(WorkspaceMotion.content, model.settings.island.visual.animationDuration)) }
    }
    func togglePin() {
        closeTask?.cancel(); closeTask = nil
        state.pinned.toggle()
        if state.pinned { state.expanded = true }
        else { scheduleAutoClose() }
    }
    func selectModule(_ module: ModuleID) {
        guard model.settings.island.modules.contains(module) else { return }
        let switching = state.overview
        state.overview = false; revealedByHover = false
        state.selected = module; requestKeyboardFocus()
        if switching { transition(to: true) }
        onVisibilityChange?()
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
        updateCompactMusic()
        if let notice = state.connectionNotice,
           !(notice.systemEvent ? settings.systemNoticesEnabled : settings.connectionNotificationsEnabled) {
            dismissConnectionNotice(collapseAutomatic: true)
        }
        for (panel, _, _) in destinations {
            let theme = settings.placementMode == .camera ? SurfaceTheme.dark : settings.visual.theme
            panel.appearance = theme == .system ? nil : NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
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
            if model.settings.island.hoverToExpand && !state.expanded && hoverTask == nil { scheduleHoverOpen() }
        } else {
            hoveredPanels.remove(ObjectIdentifier(panel))
            if hoveredPanels.isEmpty { cancelHoverOpen() }
            scheduleAutoClose()
        }
    }
    /// Hover intent: open only after the pointer rests on the notch, so sweeping
    /// across the menu bar does not flash the overview. One finite task per entry.
    private func scheduleHoverOpen() {
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WorkspaceMotion.hoverIntent))
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            guard !self.stopped, !self.hoveredPanels.isEmpty, !self.state.expanded,
                  self.model.settings.island.enabled, self.model.settings.island.hoverToExpand else { return }
            self.state.overview = self.model.settings.island.overviewOnHoverEnabled
            self.revealedByHover = self.state.overview
            self.state.focusRequest = 0; self.state.expanded = true
        }
    }
    private func cancelHoverOpen() { hoverTask?.cancel(); hoverTask = nil }
    private func scheduleAutoClose() {
        closeTask?.cancel(); closeTask = nil
        let configured = model.settings.island.autoCloseDelay
        guard !stopped, state.expanded, state.connectionNotice == nil, !state.pinned, hoveredPanels.isEmpty, configured > 0 else { return }
        // A hover peek is transient; a deliberately opened tool keeps the user's delay.
        let delay = revealedByHover && state.overview ? min(configured, WorkspaceMotion.hoverExitGrace) : configured
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            self.closeTask = nil
            // Menu tracking (Tools, player picker) runs the main run loop in
            // event-tracking mode; NSMenu.didEndTracking rearms this deadline.
            let editing = RunLoop.main.currentMode == .eventTracking || self.destinations.contains { entry in
                ((entry.panel.firstResponder as? NSTextView)?.hasMarkedText() == true) || entry.panel.childWindows?.contains(where: \.isVisible) == true
            }
            let pointerInside = self.destinations.contains { ($0.panel.isVisible && $0.panel.isOnActiveSpace && $0.panel.frame.contains(NSEvent.mouseLocation)) || ($0.cap?.isVisible == true && $0.cap?.isOnActiveSpace == true && $0.cap?.frame.contains(NSEvent.mouseLocation) == true) }
            guard self.hoveredPanels.isEmpty, !pointerInside, !editing, !self.state.pinned, self.model.settings.island.autoCloseDelay > 0 else { return }
            self.collapse()
        }
    }
    private func cameraLayout(for screen: NSScreen, expanded: Bool? = nil) -> IslandWindowLayout {
        CameraIslandGeometry.layout(screen: CameraScreenMetrics(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top, auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea, menuBarHeight: NSStatusBar.system.thickness),
            expanded: expanded ?? state.expanded, expandedWidth: expandedContentWidth,
            expandedHeight: expandedContentHeight, compactExtension: state.compactMusicTitle == nil ? 0 : 88)
    }
    private var expandedContentWidth: Double {
        if state.connectionNoticeCompact { return 340 }
        return state.overview ? 560 : model.settings.island.expandedWidth
    }
    private var expandedContentHeight: Double {
        if state.connectionNoticeCompact { return 60 }
        if state.overview { return state.connectionNotice == nil ? 140 : 190 }
        let settings = model.settings.island
        guard settings.dynamicHeightEnabled else { return settings.expandedHeight }
        let preferred: Double
        switch state.selected {
        case .calculator: preferred = 195
        case .music: preferred = sources.music.isConnected ? 170 : 150
        case .calendar: preferred = 260
        case .timer: preferred = 240
        case .system: preferred = settings.expandedHeight
        }
        return min(settings.expandedHeight, preferred + (state.connectionNotice == nil ? 0 : 70))
    }
    private func layout(duration: Double) {
        let settings = model.settings.island
        for (panel, screen, cap) in destinations {
            let available = screen.visibleFrame
            let top = max(available.minY, min(available.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 4)
            let size = NSSize(width: min(available.width, state.expanded ? expandedContentWidth : settings.width),
                              height: min(max(0, top - available.minY), state.expanded ? expandedContentHeight : (settings.minimal ? 12 : settings.height)))
            let rect: NSRect
            var capRect: NSRect?
            if settings.placementMode == .camera {
                let geometry = cameraLayout(for: screen)
                rect = geometry.bodyFrame
                capRect = geometry.capFrame
            } else {
                rect = NSRect(x: min(available.maxX - size.width, max(available.minX, screen.frame.midX - size.width / 2 + settings.offsetX)),
                              y: max(available.minY, top - size.height - settings.offsetY), width: size.width, height: size.height)
            }
            panel.hasShadow = settings.visual.shadowVisible && (state.expanded || settings.placementMode == .floating)
            guard panel.frame != rect || (capRect != nil && cap?.frame != capRect) else { continue }
            if duration > 0 {
                geometryDeadline = max(geometryDeadline, ProcessInfo.processInfo.systemUptime + duration)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration; context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: state.expanded)
                    panel.animator().setFrame(rect, display: true)
                    if let cap, let capRect { cap.animator().setFrame(capRect, display: true) }
                }
            } else {
                // Replace pending animator targets too: an interrupted expansion
                // must not restore its old frame after an immediate settings edit.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    panel.animator().setFrame(rect, display: true)
                    if let cap, let capRect { cap.animator().setFrame(capRect, display: true) }
                }
                panel.setFrame(rect, display: true)
                if let capRect { cap?.setFrame(capRect, display: true) }
            }
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
        cancelHoverOpen()
        closeTask?.cancel(); closeTask = nil; contentTask?.cancel(); contentTask = nil
        geometryTask?.cancel(); geometryTask = nil; generation += 1
    }
    func stop() {
        connectionTask?.cancel(); connectionTask = nil
        stopped = true; cancelPendingWork(); relinquishKeyboardFocus()
        destinations.forEach { $0.cap?.orderOut(nil); $0.cap?.contentView = nil; $0.cap?.close(); $0.panel.orderOut(nil); $0.panel.contentView = nil; $0.panel.close() }; destinations.removeAll()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll(); observations.removeAll(); hoveredPanels.removeAll()
    }
}
