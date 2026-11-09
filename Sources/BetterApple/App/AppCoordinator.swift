import AppKit
import SwiftUI
import Combine
import BetterAppleCore

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation, ObservableObject {
    let model: AppModel
    let calendar = CalendarService()
    let music = MusicService()
    let system = SystemStatusService()
    let bluetooth = BluetoothConnectionService()
    let nativeDock: NativeDockService
    let timer: TimerService
    let calculator: CalculatorService
    let dock: DockManager
    let shortcuts: GlobalShortcutService
    let notices = SurfaceNoticeManager()
    let registry = IslandModuleRegistry()
    private let defaults: UserDefaults
    private let bluetoothMonitoringAllowed: Bool
    private let nativeDockChangesAllowed: Bool
    lazy var widgets = WidgetManager(calendar: calendar, music: music, system: system, timer: timer, calculator: calculator, defaults: defaults)
    lazy var island = IslandManager(model: model, registry: registry, sources: IslandActivitySources(timer: timer, music: music, system: system, calendar: calendar, calculator: calculator))
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    @Published var lastSettingsSection = "General"
    private var sleeping = false
    private var applyingPreferences = false
    private var appearanceObservation: NSKeyValueObservation?

    init(defaults: UserDefaults = .standard, bluetoothMonitoringAllowed: Bool = true, nativeDockChangesAllowed: Bool = true) {
        self.defaults = defaults
        self.bluetoothMonitoringAllowed = bluetoothMonitoringAllowed
        self.nativeDockChangesAllowed = nativeDockChangesAllowed
        nativeDock = NativeDockService(defaults: defaults)
        model = AppModel(defaults: defaults)
        timer = TimerService(defaults: defaults)
        calculator = CalculatorService(defaults: defaults)
        dock = DockManager(defaults: defaults)
        shortcuts = GlobalShortcutService(defaults: defaults)
        super.init()
    }

    func start() {
        if !defaults.bool(forKey: "dock.pointerReturn.v1") {
            dock.preferences.autoHide = true
            defaults.set(true, forKey: "dock.pointerReturn.v1")
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { _, _ in
            Task { @MainActor in
                let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if let image = BrandAsset.image(darkMode: dark) { NSApp.applicationIconImage = image }
            }
        }
        model.enableCameraExperienceIfNeeded(defaults: defaults)
        dock.sources = DockActivitySources(music: music, system: system, timer: timer)
        dock.nativeDock = nativeDock
        nativeDock.onActivate = { [weak self] in
            self?.dock.preferences.enabled = true
            self?.dock.preferences.allDisplays = true
        }
        if nativeDockChangesAllowed { Task { await nativeDock.activateIfRequested() } }
        dock.onVisibilityChange = { [weak self] in self?.updateServiceDemand() }
        bluetooth.onEvent = { [weak self] event in
            self?.island.presentConnection(name: event.name, symbol: event.symbol, connected: event.connected)
        }
        shortcuts.onTrigger = { [weak self] in self?.island.toggle() }
        registry.register(NativeIslandModule(id: .calculator) { [calculator] in AnyView(CalculatorModuleView(calculator: calculator)) })
        registry.register(NativeIslandModule(id: .calendar) { [calendar] in AnyView(CalendarModuleView(calendar: calendar)) })
        registry.register(NativeIslandModule(id: .music) { [music] in AnyView(MusicModuleView(music: music)) })
        registry.register(NativeIslandModule(id: .system) { [system] in AnyView(SystemModuleView(system: system)) })
        registry.register(NativeIslandModule(id: .timer) { [timer] in AnyView(TimerModuleView(timer: timer)) })
        island.onVisibilityChange = { [weak self] in self?.updateServiceDemand() }
        widgets.onVisibilityChange = { [weak self] in self?.updateServiceDemand() }
        model.$settings.dropFirst().debounce(for: .milliseconds(120), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.island.applySettings(); self?.updateServiceDemand()
        }.store(in: &subscriptions)
        dock.$preferences.dropFirst().sink { [weak self] _ in
            guard let self, !self.applyingPreferences, self.model.settings.appearance != .custom else { return }
            self.model.settings.appearance = .custom
        }.store(in: &subscriptions)
        dock.$preferences.map(\.enabled).removeDuplicates().dropFirst().sink { [weak self] enabled in
            guard let self, !enabled, self.nativeDockChangesAllowed,
                  self.nativeDock.desiredEnabled || self.nativeDock.isActive || self.nativeDock.isBusy else { return }
            Task { try? await self.nativeDock.setEnabled(false) }
        }.store(in: &subscriptions)
        dock.$errorMessage.removeDuplicates().compactMap { $0 }.sink { [weak self] message in
            self?.notices.show(message, openSettings: { [weak self] in self?.showDockSettings() })
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
        menu.delegate = self
        let title = NSMenuItem(title: "BetterApple", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        menu.addItem(.separator())
        for (label, action, tag) in [("Dynamic Island", #selector(toggleIslandFeature), 101), ("Personalized Dock", #selector(toggleDockFeature), 102), ("Widgets", #selector(toggleWidgetsFeature), 103)] {
            let entry = NSMenuItem(title: label, action: action, keyEquivalent: "")
            entry.target = self; entry.tag = tag; menu.addItem(entry)
        }
        menu.addItem(.separator())
        for (label, action, key) in [("Open / Close Island", #selector(toggleIsland), "i"), ("Settings…", #selector(showSettings), ","), ("Edit Widgets", #selector(editWidgets), "e")] {
            let entry = NSMenuItem(title: label, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BetterApple", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        item.menu = menu; statusItem = item
    }
    @objc private func toggleIsland() { island.toggle() }
    @objc private func toggleIslandFeature() { model.settings.island.enabled.toggle() }
    @objc private func toggleDockFeature() { dock.preferences.enabled.toggle() }
    @objc private func toggleWidgetsFeature() { widgets.enabled.toggle() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 101)?.state = model.settings.island.enabled ? .on : .off
        menu.item(withTag: 102)?.state = dock.preferences.enabled ? .on : .off
        menu.item(withTag: 103)?.state = widgets.enabled ? .on : .off
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleIsland) { return model.settings.island.enabled }
        if menuItem.action == #selector(editWidgets) { return widgets.enabled }
        return true
    }
    @objc private func editWidgets() { widgets.editing.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    func showDockSettings() { lastSettingsSection = "Dock"; showSettings() }
    @objc func showSettings() {
        island.yieldKeyboardToSettings()
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
        if bluetoothMonitoringAllowed && !sleeping && model.settings.island.enabled && model.settings.island.connectionNotificationsEnabled {
            bluetooth.start()
        } else { bluetooth.stop() }
        let active = sleeping ? nil : (island.activeModule ?? island.compactModule)
        let kinds = sleeping ? Set<DesktopWidgetKind>() : widgets.activeKinds
        let dockModules = sleeping ? Set<DockModule>() : dock.activeModules
        if active == .calendar || kinds.contains(.events) { calendar.start() } else { calendar.stop() }
        if active == .music || kinds.contains(.music) || dockModules.contains(.music) { music.start() } else { music.stop() }
        if active == .system || kinds.contains(.system) || kinds.contains(.battery) || dockModules.contains(.battery) { system.start() } else { system.stop() }
        timer.setVisible(active == .timer || kinds.contains(.timer) || dockModules.contains(.timer))
    }
    func stop() {
        appearanceObservation = nil
        bluetooth.stop()
        notices.dismiss(animated: false)
        shortcuts.stop()
        widgets.flushPersistence()
        island.stop(); calendar.stop(); music.disconnect(); system.stop(); timer.setVisible(false); widgets.hide()
        subscriptions.removeAll()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
    func prepareForTermination() async -> Bool {
        guard nativeDockChangesAllowed else { return true }
        return await nativeDock.restoreForTermination()
    }
    var needsNativeDockRestoration: Bool {
        nativeDockChangesAllowed && (nativeDock.isActive || nativeDock.hasPendingRestoration || nativeDock.isBusy)
    }

    private struct SuiteConfiguration: Codable {
        var version = 1
        var app: AppSettings
        var dock: DockPreferences
        var widgets: [WidgetConfiguration]
        var shortcut: ShortcutConfiguration?
        var widgetLayout: WidgetLayoutPreferences?
        var timer: TimerPreferences?
        var calculator: CalculatorConfiguration?
        var widgetsEnabled: Bool?
        var dockNote: String?
    }
    private struct ShortcutConfiguration: Codable {
        var enabled: Bool
        var key: String
        var modifiers: String
    }
    private struct CalculatorConfiguration: Codable {
        var historyEnabled: Bool
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
        guard dock.note.count <= 100000 else { throw SettingsError.tooLarge }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let shortcut = ShortcutConfiguration(enabled: shortcuts.enabled, key: shortcuts.key.rawValue, modifiers: shortcuts.modifiers.rawValue)
        let data = try encoder.encode(SuiteConfiguration(app: model.settings, dock: dock.preferences, widgets: widgets.widgets, shortcut: shortcut, widgetLayout: widgets.layoutPreferences, timer: timer.preferences, calculator: CalculatorConfiguration(historyEnabled: calculator.historyEnabled), widgetsEnabled: widgets.enabled, dockNote: dock.note))
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
        guard suite.widgets.count <= 30, Set(suite.widgets.map(\.id)).count == suite.widgets.count else {
            throw CocoaError(.coderInvalidValue)
        }
        let dockPreferences = try suite.dock.validated()
        if let note = suite.dockNote, note.count > 100000 { throw SettingsError.tooLarge }
        let widgetConfigurations = try suite.widgets.map { try $0.validated() }
        let layout = try suite.widgetLayout?.validated()
        if let preferences = suite.timer {
            guard preferences.label.count <= 80, !preferences.presetMinutes.isEmpty, preferences.presetMinutes.count <= 8,
                  preferences.presetMinutes.allSatisfy({ (1...1440).contains($0) }) else { throw CocoaError(.coderInvalidValue) }
        }
        applyingPreferences = true
        defer { applyingPreferences = false }
        model.replaceSettings(settings); dock.preferences = dockPreferences
        if let note = suite.dockNote { dock.note = note }
        // Disable before replacing layouts so importing an off configuration cannot flash widgets.
        if suite.widgetsEnabled == false { widgets.enabled = false }
        widgets.widgets = widgetConfigurations
        if let enabled = suite.widgetsEnabled { widgets.enabled = enabled }
        if let layout { widgets.layoutPreferences = layout }
        if let preferences = suite.timer { timer.preferences = preferences.normalized() }
        if let preferences = suite.calculator { calculator.historyEnabled = preferences.historyEnabled }
        if let shortcut = suite.shortcut {
            shortcuts.enabled = false
            shortcuts.key = GlobalShortcutService.Key(rawValue: shortcut.key)!
            shortcuts.modifiers = GlobalShortcutService.Modifiers(rawValue: shortcut.modifiers)!
            shortcuts.enabled = shortcut.enabled
        }
    }
    func applyPreset(_ preset: AppearancePreset) {
        applyingPreferences = true
        defer { applyingPreferences = false }
        model.applyPreset(preset)
        dock.applyPreset(preset)
    }
}
