import AppKit
import SwiftUI
import BetterAppleCore

private struct WidgetWindowState: Equatable {
    let id: UUID
    let visible: Bool
    let x: Double, y: Double, width: Double, height: Double
    let shadow: Bool
    init(_ widget: WidgetConfiguration) {
        id = widget.id; visible = widget.visible; x = widget.x; y = widget.y
        width = widget.width; height = widget.height; shadow = widget.shadow
    }
}

@MainActor
final class WidgetManager: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: "widgets.enabled")
            if !enabled {
                editing = false
                // A feature switch tears down even panels still finishing a fade.
                let retiring = Array(retiringPanels.values)
                retiringPanels.removeAll()
                retiring.forEach { $0.orderOut(nil); $0.contentView = nil; $0.close() }
            }
            refresh()
        }
    }
    @Published var widgets: [WidgetConfiguration] {
        didSet {
            scheduleSave()
            // Note edits and SwiftUI appearance changes do not require touching AppKit windows.
            if oldValue.map(WidgetWindowState.init) != widgets.map(WidgetWindowState.init) { refresh(animated: userInitiatedChange) }
        }
    }
    @Published var editing = false {
        didSet {
            if editing && !enabled { editing = false; return }
            guard editing != oldValue else { return }
            refresh()
            if editing { panels.values.forEach { $0.orderFrontRegardless() } }
        }
    }
    @Published private(set) var layoutMessage: String?
    @Published var layoutPreferences: WidgetLayoutPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(layoutPreferences) { defaults.set(data, forKey: "widgets.editing") }
        }
    }
    let calendar: CalendarService
    let music: MusicService
    let system: SystemStatusService
    let timer: TimerService
    let calculator: CalculatorService
    private let defaults: UserDefaults
    private var panels: [UUID: NSPanel] = [:]
    private var retiringPanels: [ObjectIdentifier: NSPanel] = [:]
    private var animatingFrames = Set<UUID>()
    private var frameGenerations: [UUID: Int] = [:]
    private var delegates: [UUID: WidgetWindowDelegate] = [:]
    private var screenObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var saveWork: DispatchWorkItem?
    private var visibilityUpdateQueued = false
    private var updating = false
    private var suspended = false
    private var userInitiatedChange = false
    var onVisibilityChange: (() -> Void)?
    var activeKinds: Set<DesktopWidgetKind> {
        guard enabled, !suspended else { return [] }
        return Set(widgets.compactMap { widget in
            guard widget.visible, let panel = panels[widget.id], panel.isVisible, panel.occlusionState.contains(.visible) else { return nil }
            return widget.kind
        })
    }

    init(calendar: CalendarService, music: MusicService, system: SystemStatusService, timer: TimerService, calculator: CalculatorService? = nil, defaults: UserDefaults = .standard) {
        self.calendar = calendar; self.music = music; self.system = system; self.timer = timer; self.defaults = defaults
        self.calculator = calculator ?? CalculatorService(defaults: defaults)
        enabled = defaults.object(forKey: "widgets.enabled") as? Bool ?? true
        layoutPreferences = defaults.data(forKey: "widgets.editing").flatMap { try? JSONDecoder().decode(WidgetLayoutPreferences.self, from: $0).validated() } ?? WidgetLayoutPreferences()
        widgets = defaults.data(forKey: "widgets.layout").flatMap { try? JSONDecoder().decode([WidgetConfiguration].self, from: $0) } ?? []
        // Validate persisted geometry before allocating windows.
        var ids = Set<UUID>()
        widgets = widgets.prefix(30).map { entry in
            var value = entry.sanitized()
            if !ids.insert(value.id).inserted { value.id = UUID(); ids.insert(value.id) }
            return value
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPersistence() }
        }
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = notification.object as? NSWindow,
                      self.panels.values.contains(where: { $0 === window }) else { return }
                self.scheduleVisibilityChange()
            }
        }
    }
    func add(kind: DesktopWidgetKind) {
        guard widgets.count < 30 else { return }
        var item = WidgetConfiguration(kind: kind)
        if let screen = NSScreen.main { item.x = screen.visibleFrame.minX + 60 + Double(widgets.count % 5) * 30; item.y = screen.visibleFrame.maxY - 300 - Double(widgets.count % 5) * 30 }
        performUserChange { widgets.append(item) }
    }
    func remove(id: UUID) { performUserChange { widgets.removeAll { $0.id == id } } }
    func setAllVisible(_ visible: Bool) {
        performUserChange { widgets = widgets.map { item in var updated = item; updated.visible = visible; return updated } }
    }
    @discardableResult func duplicate(id: UUID) -> UUID? {
        guard widgets.count < 30, let original = widgets.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID(); copy.x += 24; copy.y -= 24; copy.visible = true
        let frame = constrainedFrame(NSRect(x: copy.x, y: copy.y, width: copy.width, height: copy.height))
        copy.x = frame.minX; copy.y = frame.minY
        performUserChange { widgets.append(copy) }
        return copy.id
    }
    func center(id: UUID) {
        guard let item = widgets.first(where: { $0.id == id }), let screen = panels[id]?.screen ?? NSScreen.main else { return }
        update(id) { value in value.x = screen.visibleFrame.midX - item.width / 2; value.y = screen.visibleFrame.midY - item.height / 2 }
    }
    func bringForward(id: UUID) { panels[id]?.orderFrontRegardless() }
    /// Deterministic grid layout is an explicit user action, never a background rearrangement.
    func arrangeVisible() {
        guard let screen = NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        var x = available.minX, y = available.maxY, rowHeight = 0.0
        var arranged = widgets
        var fitted = 0
        var overflow = false
        for index in arranged.indices where arranged[index].visible {
            let width = arranged[index].width, height = arranged[index].height
            if x + width > available.maxX && x > available.minX { x = available.minX; y -= rowHeight + 20; rowHeight = 0 }
            // Never wrap over widgets already placed.
            if y - height < available.minY || width > available.width || overflow { overflow = true; continue }
            arranged[index].x = x; arranged[index].y = y - height
            x += width + 20; rowHeight = max(rowHeight, height)
            fitted += 1
        }
        let visibleCount = arranged.filter(\.visible).count
        guard !overflow else {
            layoutMessage = "These \(visibleCount) widgets do not fit on this display. Resize or hide a widget and try again. Your positions have not changed."
            return
        }
        layoutMessage = "Arranged \(fitted) widgets on this display."
        performUserChange { widgets = arranged }
    }
    func finishEditingFrame(id: UUID) {
        guard editing, layoutPreferences.snapToGrid, let panel = panels[id] else { return }
        let grid = layoutPreferences.gridSize
        let frame = panel.frame
        let snapped = constrainedFrame(NSRect(x: (frame.minX / grid).rounded() * grid,
                                             y: (frame.minY / grid).rounded() * grid,
                                             width: min(800, max(220, (frame.width / grid).rounded() * grid)),
                                             height: min(800, max(160, (frame.height / grid).rounded() * grid))))
        persistFrame(snapped, id: id)
        movePanel(panel, to: snapped, id: id, animated: true)
    }
    func show() { suspended = false; refresh() }
    func hide() { suspended = true; refresh() }
    func refresh(animated: Bool = false) {
        guard !updating else { return }
        updating = true
        defer { updating = false; scheduleVisibilityChange() }
        let visibleIDs = Set(suspended || !enabled ? [] : widgets.filter(\.visible).map(\.id))
        for id in Array(panels.keys) where !visibleIDs.contains(id) {
            if let panel = panels[id] { retirePanel(panel, id: id, animated: animated && !suspended && enabled) }
            panels.removeValue(forKey: id); delegates.removeValue(forKey: id)
        }
        for item in widgets where visibleIDs.contains(item.id) {
            let panel: NSPanel
            if let existing = panels[item.id] { panel = existing }
            else {
                panel = NSPanel(contentRect: .zero, styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.titleVisibility = .hidden
                panel.titlebarAppearsTransparent = true
                panel.standardWindowButton(.closeButton)?.isHidden = true
                panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
                panel.standardWindowButton(.zoomButton)?.isHidden = true
                panel.backgroundColor = .clear; panel.isOpaque = false
                panel.level = .normal
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
                panel.isReleasedWhenClosed = false
                panel.minSize = NSSize(width: 220, height: 160)
                panel.maxSize = NSSize(width: 800, height: 800)
                let delegate = WidgetWindowDelegate(manager: self, id: item.id)
                panel.delegate = delegate; delegates[item.id] = delegate; panels[item.id] = panel
                // NSPanel starts with an empty NSView, not a nil content view.
                panel.contentView = NSHostingView(rootView: DesktopWidgetView(manager: self, id: item.id))
            }
            panel.isMovableByWindowBackground = editing
            let mask: NSWindow.StyleMask = editing ? [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel] : [.titled, .fullSizeContentView, .nonactivatingPanel]
            if panel.styleMask != mask { panel.styleMask = mask }
            panel.hasShadow = item.shadow
            let target = constrainedFrame(NSRect(x: item.x, y: item.y, width: item.width, height: item.height))
            if !NSEqualRects(panel.frame, target) { movePanel(panel, to: target, id: item.id, animated: animated && panel.isVisible) }
            if panel.contentView == nil { panel.contentView = NSHostingView(rootView: DesktopWidgetView(manager: self, id: item.id)) }
            if !panel.isVisible {
                let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                panel.alphaValue = animate ? 0 : 1
                // Startup/wake restores desktop widgets behind the user's current app.
                // Explicit add/show actions still bring the requested widget forward.
                if animated { panel.orderFrontRegardless() } else { panel.orderBack(nil) }
                if animate {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = WorkspaceMotion.standard
                        context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: true)
                        panel.animator().alphaValue = 1
                    }
                }
            }
        }
    }
    private func constrainedFrame(_ rect: NSRect) -> NSRect {
        func intersectionArea(_ screen: NSScreen) -> CGFloat {
            let overlap = screen.visibleFrame.intersection(rect)
            return overlap.isNull ? 0 : max(0, overlap.width) * max(0, overlap.height)
        }
        let best = NSScreen.screens.max { intersectionArea($0) < intersectionArea($1) }
        guard let screen = best.flatMap({ intersectionArea($0) > 0 ? $0 : nil }) ?? NSScreen.main else { return rect }
        let available = screen.visibleFrame
        let size = NSSize(width: min(rect.width, available.width), height: min(rect.height, available.height))
        return NSRect(x: max(available.minX, min(rect.minX, available.maxX - size.width)), y: max(available.minY, min(rect.minY, available.maxY - size.height)), width: size.width, height: size.height)
    }
    func persistFrame(_ frame: NSRect, id: UUID) {
        guard !updating, !animatingFrames.contains(id), let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        updating = true
        var copy = widgets
        copy[index].x = frame.minX; copy[index].y = frame.minY; copy[index].width = frame.width; copy[index].height = frame.height
        widgets = copy
        updating = false
    }
    func update(_ id: UUID, transform: (inout WidgetConfiguration) -> Void) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        performUserChange { transform(&widgets[index]) }
    }
    private func performUserChange(_ change: () -> Void) {
        let previous = userInitiatedChange
        userInitiatedChange = true
        defer { userInitiatedChange = previous }
        change()
    }
    private func movePanel(_ panel: NSPanel, to target: NSRect, id: UUID, animated: Bool) {
        frameGenerations[id, default: 0] += 1
        let generation = frameGenerations[id]!
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            animatingFrames.remove(id)
            panel.setFrame(target, display: true)
            return
        }
        animatingFrames.insert(id)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WorkspaceMotion.standard
            context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: true)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, self.panels[id] === panel, self.frameGenerations[id] == generation else { return }
                self.animatingFrames.remove(id)
            }
        }
    }
    private func retirePanel(_ panel: NSPanel, id: UUID, animated: Bool) {
        panel.delegate = nil
        animatingFrames.remove(id); frameGenerations.removeValue(forKey: id)
        let identity = ObjectIdentifier(panel)
        let close = { [weak self, panel] in
            panel.orderOut(nil); panel.contentView = nil; panel.close()
            self?.retiringPanels.removeValue(forKey: identity)
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { close(); return }
        // Keep the old panel only for this finite fade; a rapid re-show creates an independent panel.
        retiringPanels[identity] = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WorkspaceMotion.quick
            context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: false)
            panel.animator().alphaValue = 0
        } completionHandler: { Task { @MainActor in close() } }
    }
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushPersistence() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private func scheduleVisibilityChange() {
        guard !visibilityUpdateQueued else { return }
        visibilityUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.visibilityUpdateQueued = false
            self.onVisibilityChange?()
        }
    }
    func flushPersistence() {
        saveWork?.cancel(); saveWork = nil
        if let data = try? JSONEncoder().encode(widgets) { defaults.set(data, forKey: "widgets.layout") }
    }
    deinit {
        saveWork?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }
}

@MainActor
private final class WidgetWindowDelegate: NSObject, NSWindowDelegate {
    weak var manager: WidgetManager?
    let id: UUID
    init(manager: WidgetManager, id: UUID) { self.manager = manager; self.id = id }
    func windowDidMove(_ notification: Notification) { if let window = notification.object as? NSWindow { manager?.persistFrame(window.frame, id: id) } }
    func windowDidResize(_ notification: Notification) { if let window = notification.object as? NSWindow { manager?.persistFrame(window.frame, id: id) } }
    func windowDidEndLiveResize(_ notification: Notification) { manager?.finishEditingFrame(id: id) }
}
