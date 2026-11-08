#if DEBUG
import AppKit
import SwiftUI
import BetterAppleCore

@MainActor
enum FeatureToggleValidation {
    static func run(_ app: AppCoordinator, directory: URL) async throws -> [String: Bool] {
        let original = try app.configurationData()
        let originalEditing = app.widgets.editing
        defer {
            try? app.applyConfigurationData(original)
            app.widgets.editing = originalEditing
            app.island.collapse()
        }
        var checks: [String: Bool] = [:]
        var samples: [[String: Any]] = []
        func containsWidgetHost(_ view: NSView) -> Bool {
            if view is NSHostingView<DesktopWidgetView> { return true }
            return view.subviews.contains(where: containsWidgetHost)
        }
        func widgetWindows() -> [NSWindow] {
            NSApp.windows.filter { window in
                window.isVisible && window.contentView.map(containsWidgetHost) == true
            }
        }
        func dockWindows() -> [NSWindow] {
            NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)) == "DockPanel" }
        }
        func islandWindows() -> [NSWindow] {
            NSApp.windows.filter { $0.isVisible && ($0 is IslandPanel || $0 is CameraCapPanel) }
        }
        func sample(_ event: String) {
            func viewTree(_ view: NSView, depth: Int = 0) -> [String: Any] {
                ["type": String(reflecting: type(of: view)),
                 "widgetHost": view is NSHostingView<DesktopWidgetView>,
                 "hidden": view.isHidden,
                 "children": depth < 4 ? view.subviews.map { viewTree($0, depth: depth + 1) } : []]
            }
            samples.append(["event": event, "widgets": widgetWindows().count,
                            "dock": dockWindows().count, "island": islandWindows().count,
                            "widgetDemand": app.widgets.activeKinds.map(\.rawValue).sorted(),
                            "windows": NSApp.windows.map { window -> [String: Any] in
                                var item: [String: Any] = ["number": window.windowNumber,
                                    "type": String(reflecting: type(of: window)), "visible": window.isVisible,
                                    "occluded": !window.occlusionState.contains(.visible),
                                    "frame": NSStringFromRect(window.frame), "alpha": window.alphaValue]
                                if let view = window.contentView { item["content"] = viewTree(view) }
                                return item
                            }])
        }
        app.widgets.editing = false
        // Isolate this fixture from panels still retiring in earlier suite cases.
        app.widgets.enabled = false
        var note = WidgetConfiguration(kind: .notes)
        note.note = "Feature toggles preserve this local note"
        note.title = "Toggle validation"
        if let screen = NSScreen.main {
            note.x = screen.visibleFrame.minX + 24
            note.y = screen.visibleFrame.maxY - note.height - 24
        }
        var clock = WidgetConfiguration(kind: .clock)
        clock.visible = false
        let fixture = [note, clock]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let layout = try encoder.encode(fixture)
        app.widgets.widgets = fixture
        app.widgets.enabled = true
        app.widgets.show()
        app.dock.preferences.enabled = true
        app.model.settings.island.enabled = true
        app.model.settings.island.allDisplays = false
        app.model.settings.island.hoverToExpand = false
        app.model.settings.island.autoCloseDelay = 0
        app.island.collapse(); app.island.applySettings()
        try await Task.sleep(for: .milliseconds(260))
        checks["feature toggles start actual independent windows"] = widgetWindows().count == 1 && !dockWindows().isEmpty && !islandWindows().isEmpty
        sample("all_enabled")

        app.widgets.enabled = false
        app.widgets.editing = true
        try await Task.sleep(for: .milliseconds(50))
        checks["widgets master off unmounts windows and releases demand"] = widgetWindows().isEmpty && app.widgets.activeKinds.isEmpty && !app.widgets.editing
        checks["widgets master off preserves notes layout and individual visibility"] = try encoder.encode(app.widgets.widgets) == layout
        checks["widgets master toggle leaves island and dock enabled"] = app.model.settings.island.enabled && app.dock.preferences.enabled && !islandWindows().isEmpty && !dockWindows().isEmpty
        app.widgets.hide(); app.widgets.show()
        try await Task.sleep(for: .milliseconds(50))
        checks["widget wake does not override disabled feature"] = !app.widgets.enabled && widgetWindows().isEmpty && app.widgets.activeKinds.isEmpty
        sample("widgets_disabled_after_wake")

        app.model.settings.island.enabled = false
        app.island.applySettings()
        try await Task.sleep(for: .milliseconds(150))
        app.island.toggle()
        checks["island master off closes body and cap without affecting dock"] = islandWindows().isEmpty && app.island.activeModule == nil && app.island.compactModule == nil && !app.island.state.expanded && !dockWindows().isEmpty
        app.dock.preferences.enabled = false
        checks["dock master off removes actual dock windows"] = dockWindows().isEmpty && !app.dock.hovering
        sample("all_disabled")
        app.widgets.enabled = true
        try await Task.sleep(for: .milliseconds(150))
        sample("widgets_reenabled")
        checks["widgets master on restores only individually visible widgets"] = widgetWindows().count == 1 && app.widgets.widgets.first?.note == note.note && app.widgets.widgets.last?.visible == false
        checks["enabling widgets leaves other features disabled"] = islandWindows().isEmpty && dockWindows().isEmpty && !app.model.settings.island.enabled && !app.dock.preferences.enabled
        checks["widget reenable preserves complete configuration"] = try encoder.encode(app.widgets.widgets) == layout

        // Exercise disabling while a previous individual-hide fade is still retiring.
        app.widgets.setAllVisible(false)
        app.widgets.enabled = false
        checks["widgets master off immediately clears retiring windows"] = widgetWindows().isEmpty && app.widgets.activeKinds.isEmpty
        app.widgets.widgets = fixture
        app.widgets.enabled = true
        app.widgets.enabled = false
        app.widgets.enabled = true
        app.widgets.enabled = false
        try await Task.sleep(for: .milliseconds(200))
        let reversedLayout = try encoder.encode(app.widgets.widgets)
        checks["rapid widget master reversal settles fully disabled"] = widgetWindows().isEmpty && app.widgets.activeKinds.isEmpty && reversedLayout == layout

        let disabledSuite = try app.configurationData()
        app.widgets.enabled = true
        try app.applyConfigurationData(disabledSuite)
        let importedLayout = try encoder.encode(app.widgets.widgets)
        checks["suite roundtrip restores disabled widget feature"] = !app.widgets.enabled && importedLayout == layout
        var legacy = try JSONSerialization.jsonObject(with: disabledSuite) as! [String: Any]
        legacy.removeValue(forKey: "widgetsEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        app.widgets.enabled = true
        try app.applyConfigurationData(legacyData)
        let preservesOn = app.widgets.enabled
        app.widgets.enabled = false
        try app.applyConfigurationData(legacyData)
        checks["legacy suite preserves current widget feature choice"] = preservesOn && !app.widgets.enabled

        let suiteName = "app.betterapple.feature-persistence.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = WidgetManager(calendar: app.calendar, music: app.music, system: app.system,
                                    timer: app.timer, calculator: app.calculator, defaults: defaults)
        checks["new widget installation defaults to enabled"] = manager.enabled
        manager.widgets = fixture
        manager.enabled = false
        manager.flushPersistence()
        let restored = WidgetManager(calendar: app.calendar, music: app.music, system: app.system,
                                     timer: app.timer, calculator: app.calculator, defaults: defaults)
        restored.show()
        let persistedLayout = try encoder.encode(restored.widgets)
        checks["widget disabled state persists independently from layout"] = !restored.enabled && restored.activeKinds.isEmpty && persistedLayout == layout
        restored.hide(); manager.hide()
        sample("validation_complete")
        try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("feature-toggles.json"))
        return checks
    }
}
#endif
