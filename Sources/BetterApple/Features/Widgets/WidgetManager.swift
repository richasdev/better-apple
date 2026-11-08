import AppKit
import SwiftUI
import BetterAppleCore

enum DesktopWidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, analogClock, calendar, events, calculator, music, battery, system, notes, timer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .analogClock: return "Analog Clock"
        case .events: return "Upcoming Events"
        case .system: return "CPU & Memory"
        default: return rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .clock, .analogClock: return "clock"
        case .calendar, .events: return "calendar"
        case .calculator: return "plus.forwardslash.minus"
        case .music: return "music.note"
        case .battery: return "battery.100percent"
        case .system: return "cpu"
        case .notes: return "note.text"
        case .timer: return "timer"
        }
    }
}

enum DesktopWidgetTheme: String, Codable, CaseIterable, Identifiable {
    case automatic, light, dark
    var id: String { rawValue }
}

enum DesktopWidgetAccent: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, orange, green, graphite
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .graphite: return .gray
        }
    }
}

struct WidgetConfiguration: Codable, Identifiable {
    var id = UUID()
    var kind: DesktopWidgetKind
    var visible = true
    var x: Double = 80
    var y: Double = 100
    var width: Double = 300
    var height: Double = 240
    var opacity: Double = 0.95
    var theme: DesktopWidgetTheme = .automatic
    var shadow = true
    var border = true
    var note = ""
    var accent: DesktopWidgetAccent?
}

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
    @Published var widgets: [WidgetConfiguration] {
        didSet {
            scheduleSave()
            // Note edits and SwiftUI appearance changes do not require touching AppKit windows.
            if oldValue.map(WidgetWindowState.init) != widgets.map(WidgetWindowState.init) { refresh() }
        }
    }
    @Published var editing = false { didSet { refresh() } }
    let calendar: CalendarService
    let music: MusicService
    let system: SystemStatusService
    let timer: TimerService
    private let defaults: UserDefaults
    private var panels: [UUID: NSPanel] = [:]
    private var delegates: [UUID: WidgetWindowDelegate] = [:]
    private var screenObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var saveWork: DispatchWorkItem?
    private var visibilityUpdateQueued = false
    private var updating = false
    private var suspended = false
    var onVisibilityChange: (() -> Void)?
    var activeKinds: Set<DesktopWidgetKind> {
        guard !suspended else { return [] }
        return Set(widgets.compactMap { widget in
            guard widget.visible, let panel = panels[widget.id], panel.isVisible, panel.occlusionState.contains(.visible) else { return nil }
            return widget.kind
        })
    }

    init(calendar: CalendarService, music: MusicService, system: SystemStatusService, timer: TimerService, defaults: UserDefaults = .standard) {
        self.calendar = calendar; self.music = music; self.system = system; self.timer = timer; self.defaults = defaults
        widgets = defaults.data(forKey: "widgets.layout").flatMap { try? JSONDecoder().decode([WidgetConfiguration].self, from: $0) } ?? []
        // Validate persisted geometry before allocating windows.
        widgets = widgets.prefix(30).map { entry in
            var value = entry
            value.width = Self.clamp(value.width, 220...800, fallback: 300)
            value.height = Self.clamp(value.height, 160...800, fallback: 240)
            value.opacity = Self.clamp(value.opacity, 0.2...1, fallback: 0.95)
            if !value.x.isFinite { value.x = 80 }; if !value.y.isFinite { value.y = 100 }
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
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double { value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback }
    func add(kind: DesktopWidgetKind) {
        guard widgets.count < 30 else { return }
        var item = WidgetConfiguration(kind: kind)
        if let screen = NSScreen.main { item.x = screen.visibleFrame.minX + 60 + Double(widgets.count % 5) * 30; item.y = screen.visibleFrame.maxY - 300 - Double(widgets.count % 5) * 30 }
        widgets.append(item)
    }
    func remove(id: UUID) { widgets.removeAll { $0.id == id } }
    func show() { suspended = false; refresh() }
    func hide() { suspended = true; refresh() }
    func refresh() {
        guard !updating else { return }
        updating = true
        defer { updating = false; scheduleVisibilityChange() }
        let visibleIDs = Set(suspended ? [] : widgets.filter(\.visible).map(\.id))
        for id in Array(panels.keys) where !visibleIDs.contains(id) {
            panels[id]?.orderOut(nil)
            panels[id]?.contentView = nil
            panels[id]?.delegate = nil
            panels[id]?.close()
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
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
                panel.isReleasedWhenClosed = false
                panel.minSize = NSSize(width: 220, height: 160)
                let delegate = WidgetWindowDelegate(manager: self, id: item.id)
                panel.delegate = delegate; delegates[item.id] = delegate; panels[item.id] = panel
            }
            panel.isMovableByWindowBackground = editing
            let mask: NSWindow.StyleMask = editing ? [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel] : [.titled, .fullSizeContentView, .nonactivatingPanel]
            if panel.styleMask != mask { panel.styleMask = mask }
            panel.hasShadow = item.shadow
            let target = constrainedFrame(NSRect(x: item.x, y: item.y, width: item.width, height: item.height))
            if !NSEqualRects(panel.frame, target) { panel.setFrame(target, display: true) }
            if panel.contentView == nil { panel.contentView = NSHostingView(rootView: DesktopWidgetView(manager: self, id: item.id)) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }
    private func constrainedFrame(_ rect: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) ?? NSScreen.main else { return rect }
        let available = screen.visibleFrame
        let size = NSSize(width: min(rect.width, available.width), height: min(rect.height, available.height))
        return NSRect(x: max(available.minX, min(rect.minX, available.maxX - size.width)), y: max(available.minY, min(rect.minY, available.maxY - size.height)), width: size.width, height: size.height)
    }
    func persistFrame(_ frame: NSRect, id: UUID) {
        guard !updating, let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        updating = true
        var copy = widgets
        copy[index].x = frame.minX; copy[index].y = frame.minY; copy[index].width = frame.width; copy[index].height = frame.height
        widgets = copy
        updating = false
    }
    func update(_ id: UUID, transform: (inout WidgetConfiguration) -> Void) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        transform(&widgets[index])
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
}

struct WidgetSettingsView: View {
    @ObservedObject var manager: WidgetManager
    var body: some View {
        Form {
            Section("Desktop Widgets") {
                Toggle("Edit layout", isOn: $manager.editing)
                Text("In edit mode, drag the widget background to move it and resize from its edges. Layouts are saved automatically.").font(.caption).foregroundStyle(.secondary)
                Menu("Add widget") { ForEach(DesktopWidgetKind.allCases) { kind in Button(kind.title, systemImage: kind.symbol) { manager.add(kind: kind) } } }
            }
            ForEach(manager.widgets) { item in
                Section(item.kind.title) {
                    Toggle("Visible", isOn: binding(item, \.visible))
                    Picker("Theme", selection: binding(item, \.theme)) { ForEach(DesktopWidgetTheme.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("Accent color", selection: binding(item, \.accent)) {
                        Text("System accent").tag(Optional<DesktopWidgetAccent>.none)
                        ForEach(DesktopWidgetAccent.allCases) { accent in Text(accent.rawValue.capitalized).tag(Optional(accent)) }
                    }
                    LabeledContent("Opacity") { Slider(value: binding(item, \.opacity), in: 0.2...1).frame(width: 180) }
                    Toggle("Border", isOn: binding(item, \.border))
                    Toggle("Shadow", isOn: binding(item, \.shadow))
                    Button("Remove widget", role: .destructive) { manager.remove(id: item.id) }
                }
            }
        }.formStyle(.grouped)
    }
    private func binding<T>(_ item: WidgetConfiguration, _ keyPath: WritableKeyPath<WidgetConfiguration, T>) -> Binding<T> {
        Binding(get: { (manager.widgets.first { $0.id == item.id } ?? item)[keyPath: keyPath] }, set: { value in manager.update(item.id) { $0[keyPath: keyPath] = value } })
    }
}
