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
            checks["island expanded"] = app.island.activeModule == .calculator
            captureWindows(to: directory, prefix: "island")
            app.dock.show()
            checks["dock resolves real applications"] = !app.dock.applications.isEmpty
            for kind in DesktopWidgetKind.allCases { app.widgets.add(kind: kind) }
            app.widgets.editing = true
            try await Task.sleep(for: .milliseconds(500))
            checks["all widget kinds created"] = app.widgets.widgets.count == DesktopWidgetKind.allCases.count
            let notes = app.widgets.widgets.first { $0.kind == .notes }!
            app.widgets.update(notes.id) { $0.note = "Runtime validation — persisted locally" }
            app.widgets.flushPersistence()
            checks["notes updated"] = app.widgets.widgets.first { $0.id == notes.id }?.note == "Runtime validation — persisted locally"
            let exported = try app.configurationData()
            app.model.settings.island.width = 321
            try app.applyConfigurationData(exported)
            checks["suite JSON restores actual settings and widgets"] = app.model.settings.island.width == 220 && app.widgets.widgets.count == 10 && app.widgets.widgets.first { $0.id == notes.id }?.note == "Runtime validation — persisted locally"
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
