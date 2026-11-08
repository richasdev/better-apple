#if DEBUG
import AppKit
import BetterAppleCore

/// Exercises the real managers without Calendar/Automation prompts or changing the user's layout.
@MainActor
enum RuntimeValidation {
    static func run(_ app: AppCoordinator) async {
        let directory = URL(fileURLWithPath: "/tmp/BetterApple-validation", isDirectory: true)
        var checks: [String: Bool] = [:]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await Task.sleep(for: .milliseconds(500))
            checks["settings window presented"] = NSApp.windows.contains { $0.title == "BetterApple" && $0.isVisible }
            captureWindows(to: directory, prefix: "settings")
            checks["safe calculator evaluates"] = try Calculator.evaluate("(24 + 18) / 6") == 7
            app.model.settings.island.hoverToExpand = false
            app.model.settings.island.autoCloseDelay = 0
            app.island.state.selected = .calculator
            app.island.state.expanded = true
            try await Task.sleep(for: .milliseconds(500))
            checks["island window expanded"] = app.island.state.expanded && NSApp.windows.contains {
                $0 is IslandPanel && $0.isVisible && $0.frame.width >= 419 && $0.frame.height >= 249
            }
            let islandWindows = Set(NSApp.windows.filter { $0 is IslandPanel && $0.isVisible }.map(\.windowNumber))
            app.calculator.expression = "6 * 7"
            app.applyPreset(.glass)
            checks["workspace preset remains selected"] = app.model.settings.appearance == .glass && app.dock.preferences.material == .glass
            app.model.settings.island.visual.theme = .light
            app.model.settings.island.visual.accent = .orange
            app.island.applySettings()
            checks["appearance updates preserve island window and calculation"] = islandWindows == Set(NSApp.windows.filter { $0 is IslandPanel && $0.isVisible }.map(\.windowNumber)) && app.calculator.resultText == "42" && app.model.settings.appearance == .custom
            app.island.togglePin()
            checks["island pin and dismiss"] = app.island.state.pinned && app.island.state.expanded
            app.island.collapse()
            checks["island pin and dismiss"] = checks["island pin and dismiss"] == true && !app.island.state.pinned && !app.island.state.expanded
            app.island.state.expanded = true
            app.calculator.historyEnabled = true
            app.calculator.commit()
            checks["shared calculator commits optional history"] = app.calculator.history.count == 1 && app.widgets.calculator === app.calculator
            captureWindows(to: directory, prefix: "island")
            app.dock.show()
            checks["dock resolves real applications"] = !app.dock.applications.isEmpty
            for kind in DesktopWidgetKind.allCases { app.widgets.add(kind: kind) }
            app.widgets.editing = true
            try await Task.sleep(for: .milliseconds(500))
            checks["all widget kinds created"] = app.widgets.widgets.count == DesktopWidgetKind.allCases.count
            let notes = app.widgets.widgets.first { $0.kind == .notes }!
            app.widgets.update(notes.id) { $0.note = "Runtime validation — persisted locally" }
            app.widgets.update(notes.id) { $0.title = "Workspace note"; $0.fontSize = 18; $0.accent = .purple }
            let duplicateID = app.widgets.duplicate(id: notes.id)
            let duplicate = app.widgets.widgets.first { $0.id == duplicateID }
            checks["widget duplication preserves note and appearance"] = duplicate?.note == "Runtime validation — persisted locally" && duplicate?.title == "Workspace note" && duplicate?.fontSize == 18 && duplicate?.id != notes.id
            if let duplicateID { app.widgets.remove(id: duplicateID) }
            app.widgets.layoutPreferences = WidgetLayoutPreferences(snapToGrid: true, gridSize: 24)
            app.timer.label = "Focus"
            app.timer.completionSound = .silent
            app.timer.addPreset(minutes: 10)
            app.widgets.flushPersistence()
            checks["notes updated"] = app.widgets.widgets.first { $0.id == notes.id }?.note == "Runtime validation — persisted locally"
            let exported = try app.configurationData()
            app.model.settings.island.width = 321
            app.widgets.layoutPreferences.snapToGrid = false
            app.timer.label = "Changed"
            try app.applyConfigurationData(exported)
            checks["suite JSON restores actual settings and widgets"] = app.model.settings.island.width == 220 && app.widgets.widgets.count == 10 && app.widgets.widgets.first { $0.id == notes.id }?.note == "Runtime validation — persisted locally"
            checks["suite restores new personalization"] = app.model.settings.island.visual.theme == .light && app.model.settings.island.visual.accent == .orange && app.widgets.layoutPreferences.snapToGrid && app.timer.label == "Focus" && app.widgets.widgets.first { $0.id == notes.id }?.fontSize == 18
            var legacy = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
            legacy.removeValue(forKey: "timer"); legacy.removeValue(forKey: "calculator"); legacy.removeValue(forKey: "widgetLayout")
            var legacyApp = legacy["app"] as! [String: Any]
            var legacyIsland = legacyApp["island"] as! [String: Any]; legacyIsland.removeValue(forKey: "appearance")
            legacyApp["island"] = legacyIsland; legacy["app"] = legacyApp
            var legacyDock = legacy["dock"] as! [String: Any]
            for key in ["theme", "material", "accent", "cornerRadius", "magnification", "animationDuration", "showLabels", "showRunningApplications", "allDisplays"] { legacyDock.removeValue(forKey: key) }
            legacy["dock"] = legacyDock
            legacy["widgets"] = (legacy["widgets"] as! [[String: Any]]).map { entry -> [String: Any] in var value = entry; value.removeValue(forKey: "title"); value.removeValue(forKey: "fontSize"); value.removeValue(forKey: "options"); return value }
            try app.applyConfigurationData(JSONSerialization.data(withJSONObject: legacy))
            checks["legacy suite imports without losing notes"] = app.widgets.widgets.first { $0.id == notes.id }?.note == "Runtime validation — persisted locally" && app.model.settings.island.visual == IslandAppearance()
            try app.applyConfigurationData(exported)
            var invalid = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
            invalid["version"] = 999
            do {
                try app.applyConfigurationData(JSONSerialization.data(withJSONObject: invalid))
                checks["invalid suite import preserves settings"] = false
            } catch {
                checks["invalid suite import preserves settings"] = app.model.settings.island.width == 220 && app.widgets.widgets.count == 10
            }
            captureWindows(to: directory, prefix: "widgets")
            app.timer.start(seconds: 1)
            try await Task.sleep(for: .milliseconds(1300))
            checks["timer completed"] = app.timer.didComplete
            app.widgets.widgets.indices.forEach { app.widgets.widgets[$0].visible = false }
            try await Task.sleep(for: .milliseconds(150))
            checks["hidden widgets release demand"] = app.widgets.activeKinds.isEmpty
            app.island.collapse()
            try await Task.sleep(for: .milliseconds(300))
            checks["compact island releases demand"] = app.island.activeModule == nil
            let result: [String: Any] = ["checks": checks, "passed": checks.values.allSatisfy { $0 }, "windowCount": NSApp.windows.count]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("result.json"))
            print("Runtime validation: \(checks.values.allSatisfy { $0 } ? "PASS" : "FAIL") — \(directory.path)")
        } catch {
            try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("error.txt"))
        }
        NSApp.terminate(nil)
    }
    private static func captureWindows(to directory: URL, prefix: String) {
        for (index, window) in NSApp.windows.filter({ $0.isVisible }).enumerated() {
            guard let view = window.contentView else { continue }
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(prefix)-\(index).png"))
        }
    }
}
#endif
