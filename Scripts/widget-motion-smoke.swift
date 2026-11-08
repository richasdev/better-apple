import AppKit
import Foundation

@main struct WidgetMotionSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let suite = "app.betterapple.widget-motion.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WidgetManager(calendar: CalendarService(), music: MusicService(), system: SystemStatusService(), timer: TimerService(defaults: defaults), defaults: defaults)
        manager.add(kind: .notes)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        let id = manager.widgets[0].id
        let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
        assert(abs(panel.alphaValue - 1) < 0.001)
        let content = panel.contentView
        manager.editing = true
        manager.update(id) { $0.note = "Preserved while moving" }
        assert(panel.contentView === content)
        manager.center(id: id)
        let centered = manager.widgets[0]
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        assert(manager.widgets[0].x == centered.x && manager.widgets[0].y == centered.y)
        manager.update(id) { $0.x += 41; $0.y -= 23 }
        let retargeted = manager.widgets[0]
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        assert(abs(panel.frame.minX - retargeted.x) < 1 && abs(panel.frame.minY - retargeted.y) < 1)
        assert(manager.widgets[0].x == retargeted.x && manager.widgets[0].note == "Preserved while moving")
        manager.layoutPreferences.snapToGrid = true
        manager.finishEditingFrame(id: id)
        let snapped = manager.widgets[0]
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        assert(abs(panel.frame.minX - snapped.x) < 1 && abs(panel.frame.minY - snapped.y) < 1)
        assert(abs(snapped.x.truncatingRemainder(dividingBy: 20)) < 0.001)
        manager.update(id) { $0.visible = false }
        assert(manager.activeKinds.isEmpty)
        manager.update(id) { $0.visible = true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        assert(NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.count == 1)
        assert(manager.widgets[0].note == "Preserved while moving")
        manager.remove(id: id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        assert(NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.isEmpty)
        manager.hide()
        for _ in 0..<4 { manager.add(kind: .clock) }
        manager.widgets.indices.forEach { manager.widgets[$0].width = 800; manager.widgets[$0].height = 800 }
        let originalOrigins = manager.widgets.map { CGPoint(x: $0.x, y: $0.y) }
        manager.arrangeVisible()
        assert(manager.widgets.map { CGPoint(x: $0.x, y: $0.y) } == originalOrigins)
        assert(manager.layoutMessage?.contains("have not changed") == true)
        manager.setAllVisible(false)
        manager.flushPersistence()
        print("PASS: real widget show/fade/retarget/snap/removal, no transient frame persistence, note hosting identity, rapid re-show isolation, overflow arrangement preserves layout.")
    }
}
