import AppKit
import SwiftUI
import Combine
import BetterAppleCore

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate {
    let model: AppModel
    let calendar = CalendarService()
    let music = MusicService()
    let system = SystemStatusService()
    let timer = TimerService()
    let dock: DockManager
    let shortcuts: GlobalShortcutService
    let registry = IslandModuleRegistry()
    private let defaults: UserDefaults
    lazy var widgets = WidgetManager(calendar: calendar, music: music, system: system, timer: timer, defaults: defaults)
    lazy var island = IslandManager(model: model, registry: registry)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        model = AppModel(defaults: defaults)
        dock = DockManager(defaults: defaults)
        shortcuts = GlobalShortcutService(defaults: defaults)
        super.init()
    }

    func start() {
        shortcuts.onTrigger = { [weak self] in self?.island.toggle() }
        registry.register(NativeIslandModule(id: .calculator) { AnyView(CalculatorModuleView()) })
        registry.register(NativeIslandModule(id: .calendar) { [calendar] in AnyView(CalendarModuleView(calendar: calendar)) })
        registry.register(NativeIslandModule(id: .music) { [music] in AnyView(MusicModuleView(music: music)) })
        registry.register(NativeIslandModule(id: .system) { [system] in AnyView(SystemModuleView(system: system)) })
        registry.register(NativeIslandModule(id: .timer) { [timer] in AnyView(TimerModuleView(timer: timer)) })
        island.onVisibilityChange = { [weak self] in self?.updateServiceDemand() }
        widgets.onVisibilityChange = { [weak self] in self?.updateServiceDemand() }
        model.$settings.dropFirst().debounce(for: .milliseconds(120), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.island.rebuild(); self?.updateServiceDemand()
        }.store(in: &subscriptions)
        widgets.$widgets.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.updateServiceDemand() }
        }.store(in: &subscriptions)
        makeMenu()
        island.rebuild(); dock.refresh(); widgets.show(); updateServiceDemand()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = true; self?.island.collapse(); self?.widgets.hide(); self?.updateServiceDemand() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = false; self?.island.rebuild(); self?.widgets.show(); self?.updateServiceDemand() }
            })
        }
        if !defaults.bool(forKey: "onboarding.completed") {
            showSettings(); defaults.set(true, forKey: "onboarding.completed")
        }
    }
    private func makeMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "BetterApple")
        let menu = NSMenu()
        let title = NSMenuItem(title: "BetterApple", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        menu.addItem(.separator())
        for (label, action, key) in [("Open / Close Island", #selector(toggleIsland), "i"), ("Settings…", #selector(showSettings), ","), ("Edit Widgets", #selector(editWidgets), "e")] {
            let entry = NSMenuItem(title: label, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BetterApple", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        item.menu = menu; statusItem = item
    }
    @objc private func toggleIsland() { island.toggle() }
    @objc private func editWidgets() { widgets.editing.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "BetterApple"; window.minSize = NSSize(width: 760, height: 540)
            window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsRootView(model: model, dock: dock, widgets: widgets, calendar: calendar, music: music, coordinator: self))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        window.contentView = nil; settingsWindow = nil
    }
    private func updateServiceDemand() {
        let active = sleeping ? nil : island.activeModule
        let kinds = sleeping ? Set<DesktopWidgetKind>() : widgets.activeKinds
        if active == .calendar || kinds.contains(.events) { calendar.start() } else { calendar.stop() }
        if active == .music || kinds.contains(.music) { music.start() } else { music.stop() }
        if active == .system || kinds.contains(.system) || kinds.contains(.battery) { system.start() } else { system.stop() }
        timer.setVisible(active == .timer || kinds.contains(.timer))
    }
    func stop() {
        shortcuts.stop()
        widgets.flushPersistence()
        island.stop(); calendar.stop(); music.disconnect(); system.stop(); timer.setVisible(false); widgets.hide()
        subscriptions.removeAll()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private struct SuiteConfiguration: Codable {
        var version = 1
        var app: AppSettings
        var dock: DockPreferences
        var widgets: [WidgetConfiguration]
        var shortcut: ShortcutConfiguration?
    }
    private struct ShortcutConfiguration: Codable {
        var enabled: Bool
        var key: String
        var modifiers: String
    }
    func exportConfiguration() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "BetterApple.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try configurationData().write(to: url, options: .atomic)
        } catch { model.persistenceError = error.localizedDescription }
    }
    func configurationData() throws -> Data {
        guard widgets.widgets.allSatisfy({ $0.note.count <= 100000 }) else { throw SettingsError.tooLarge }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let shortcut = ShortcutConfiguration(enabled: shortcuts.enabled, key: shortcuts.key.rawValue, modifiers: shortcuts.modifiers.rawValue)
        let data = try encoder.encode(SuiteConfiguration(app: model.settings, dock: dock.preferences, widgets: widgets.widgets, shortcut: shortcut))
        guard data.count <= 2 * 1024 * 1024 else { throw SettingsError.tooLarge }
        return data
    }
    func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 2 * 1024 * 1024 { throw SettingsError.tooLarge }
            try applyConfigurationData(Data(contentsOf: url))
        } catch { model.persistenceError = error.localizedDescription }
    }
    func applyConfigurationData(_ data: Data) throws {
        guard data.count <= 2 * 1024 * 1024 else { throw SettingsError.tooLarge }
        let suite = try JSONDecoder().decode(SuiteConfiguration.self, from: data)
        guard suite.version == 1 else { throw SettingsError.unsupportedVersion(suite.version) }
        let settings = try suite.app.validated()
        if let shortcut = suite.shortcut {
            guard GlobalShortcutService.Key(rawValue: shortcut.key) != nil,
                  GlobalShortcutService.Modifiers(rawValue: shortcut.modifiers) != nil else { throw CocoaError(.coderInvalidValue) }
        }
        guard suite.widgets.count <= 30, suite.dock.applicationPaths.count <= 100,
              suite.dock.iconSize.isFinite, suite.dock.spacing.isFinite, suite.dock.opacity.isFinite,
              (24...80).contains(suite.dock.iconSize), (0...24).contains(suite.dock.spacing), (0.2...1).contains(suite.dock.opacity),
              suite.dock.applicationPaths.allSatisfy({ $0.hasPrefix("/") && $0.hasSuffix(".app") }),
              Set(suite.widgets.map(\.id)).count == suite.widgets.count,
              suite.widgets.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (220...800).contains($0.width) && (160...800).contains($0.height) && (0.2...1).contains($0.opacity) && $0.note.count <= 100000 }) else {
            throw CocoaError(.coderInvalidValue)
        }
        model.settings = settings; dock.preferences = suite.dock; widgets.widgets = suite.widgets
        if let shortcut = suite.shortcut {
            shortcuts.enabled = false
            shortcuts.key = GlobalShortcutService.Key(rawValue: shortcut.key)!
            shortcuts.modifiers = GlobalShortcutService.Modifiers(rawValue: shortcut.modifiers)!
            shortcuts.enabled = shortcut.enabled
        }
    }
    func applyPreset(_ preset: AppearancePreset) {
        model.settings.applyPreset(preset)
        dock.preferences.iconSize = model.settings.dock.iconSize
        dock.preferences.spacing = model.settings.dock.spacing
        dock.preferences.opacity = model.settings.dock.opacity
    }
}
