#if DEBUG
import AppKit
import BetterAppleCore

@MainActor
enum WorkspaceReferenceValidation {
    static func run(_ app: AppCoordinator, directory: URL) async throws -> [String: Bool] {
        let original = try app.configurationData()
        defer { try? app.applyConfigurationData(original); app.timer.cancel() }
        var checks: [String: Bool] = [:]
        checks["adaptive logo variants and macOS app icon are bundled"] = BrandAsset.image(darkMode: true) != nil && BrandAsset.image(darkMode: false) != nil && Bundle.main.url(forResource: "BetterApple", withExtension: "icns") != nil
        let apps = app.dock.preferences.applicationPaths
        app.dock.preferences.enabled = false
        app.dock.note = "Shared local Dock note"
        app.dock.applyLayoutPreset(.floating)
        checks["reference Dock preset preserves disabled state pinned apps and note"] = !app.dock.preferences.enabled && app.dock.preferences.applicationPaths == apps && app.dock.note == "Shared local Dock note" && app.dock.preferences.presentation == .floating
        checks["Dock modules use the actual shared services"] = app.dock.sources?.music === app.music && app.dock.sources?.timer === app.timer && app.dock.sources?.system === app.system
        var clock = WidgetConfiguration(kind: .clock)
        clock.apply(.desktopClock)
        var battery = WidgetConfiguration(kind: .battery)
        battery.apply(.statusBar)
        var note = WidgetConfiguration(kind: .notes)
        note.note = "A preserved desktop note"
        note.apply(.pureBlack)
        app.widgets.widgets = [clock, battery, note]
        app.widgets.enabled = false
        let exported = try app.configurationData()
        app.dock.note = "Changed"
        app.dock.preferences.enabledModules = [.apps]
        app.widgets.widgets = []
        try app.applyConfigurationData(exported)
        checks["suite restores modular Dock layout and local note"] = app.dock.preferences.presentation == .floating && Set(app.dock.preferences.enabledModules) == Set(DockModule.allCases) && app.dock.note == "Shared local Dock note"
        checks["suite restores desktop clock compact status and pure black widgets"] = app.widgets.widgets.count == 3 && app.widgets.widgets[0].surface == .minimal && app.widgets.widgets[0].textSize > 100 && app.widgets.widgets[1].height < 160 && app.widgets.widgets[2].theme == .dark && app.widgets.widgets[2].opacity == 1 && app.widgets.widgets[2].note == note.note
        var legacy = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        legacy.removeValue(forKey: "dockNote")
        app.dock.note = "Keep local note on legacy import"
        try app.applyConfigurationData(JSONSerialization.data(withJSONObject: legacy))
        checks["legacy suite preserves local Dock note"] = app.dock.note == "Keep local note on legacy import"
        var oversized = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        oversized["dockNote"] = String(repeating: "x", count: 100001)
        let before = try app.configurationData()
        do {
            try app.applyConfigurationData(JSONSerialization.data(withJSONObject: oversized))
            checks["oversized Dock note import rejected before any mutation"] = false
        } catch {
            checks["oversized Dock note import rejected before any mutation"] = try app.configurationData() == before
        }
        app.dock.preferences.enabled = true
        app.dock.preferences.autoHide = false
        app.dock.preferences.allDisplays = true
        app.showDockSettings()
        try await Task.sleep(for: .milliseconds(260))
        let panels = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)) == "DockPanel" }
        checks["modular Dock creates native panels with a reference layout"] = !panels.isEmpty && panels.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 }
        let visibleDemand = app.dock.activeModules
        app.timer.start(seconds: 2)
        try await Task.sleep(for: .milliseconds(1150))
        if visibleDemand.contains(.timer) && app.dock.activeModules.contains(.timer) {
            checks["visible modular Dock drives the real shared timer display"] = app.timer.isRunning && app.timer.remaining < 1.7
        } else {
            checks["occluded modular Dock suspends timer display sampling"] = app.dock.activeModules.isEmpty && app.timer.remaining >= 1.7
        }
        app.timer.cancel()
        app.dock.preferences.enabled = false
        checks["disabled modular Dock releases all service demand"] = app.dock.activeModules.isEmpty
        let report: [String: Any] = ["checks": checks, "moduleTypes": DockModule.allCases.map(\.rawValue),
            "widgetStyles": ["desktop clock", "compact status", "pure black"], "notesContentOmitted": true,
            "visibleDockDemandObserved": visibleDemand.map(\.rawValue).sorted(),
            "occlusionFlags": panels.map { $0.occlusionState.rawValue }]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("workspace-reference.json"))
        return checks
    }
}
#endif
