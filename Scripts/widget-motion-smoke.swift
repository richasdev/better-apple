import AppKit
import Foundation
import SwiftUI

@main struct WidgetMotionSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let suite = "app.betterapple.widget-motion.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = WidgetManager(calendar: CalendarService(), music: MusicService(), system: SystemStatusService(), timer: TimerService(defaults: defaults), defaults: defaults)
        manager.add(kind: .notes)
        RunLoop.main.run(until: Date().addingTimeInterval(0.75))
        let id = manager.widgets[0].id
        let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
        assert(abs(panel.alphaValue - 1) < 0.001)
        guard let hosting = panel.contentView as? NSHostingView<DesktopWidgetView> else {
            fatalError("A new widget must mount its SwiftUI content, not the default empty NSView")
        }
        assert(hosting.rootView.id == id && hosting.rootView.manager === manager)
        let content = panel.contentView
        manager.editing = true
        manager.update(id) { $0.note = "Ready for native editing" }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func textEditor(in view: NSView) -> NSTextView? {
            if let editor = view as? NSTextView, !editor.isFieldEditor { return editor }
            return view.subviews.lazy.compactMap { textEditor(in: $0) }.first
        }
        guard let editor = textEditor(in: hosting) else { fatalError("Mounted note widget must contain its native TextEditor") }
        assert(editor.string == "Ready for native editing")
        editor.insertText("Preserved while moving", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        assert(manager.widgets[0].note == "Preserved while moving")
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
        let restoredPanel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
        guard let restoredHosting = restoredPanel.contentView as? NSHostingView<DesktopWidgetView> else {
            fatalError("Re-shown widgets must recreate their mounted SwiftUI content")
        }
        assert(restoredHosting !== hosting)
        assert(textEditor(in: restoredHosting)?.string == "Preserved while moving")
        assert(manager.widgets[0].note == "Preserved while moving")
        manager.remove(id: id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        assert(NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.isEmpty)
        let snapshotDirectory = ProcessInfo.processInfo.environment["BETTERAPPLE_WIDGET_SNAPSHOTS"]
        func capture(_ panel: NSWindow, name: String) throws {
            guard let snapshotDirectory, let view = panel.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try png.write(to: URL(fileURLWithPath: snapshotDirectory).appendingPathComponent(name))
        }
        manager.editing = false
        manager.add(kind: .clock)
        let clockID = manager.widgets[0].id
        manager.update(clockID) { $0.apply(.desktopClock) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let clockPanel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
        assert(clockPanel.frame.width == 620 && clockPanel.frame.height == 250)
        assert(!clockPanel.hasShadow)
        try capture(clockPanel, name: "BetterApple-desktop-widget.png")
        let clockHosting = clockPanel.contentView
        manager.update(clockID) { $0.width = 220; $0.height = 72; $0.fontSize = 200 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        assert(clockPanel.contentView === clockHosting && clockPanel.frame.width == 220 && clockPanel.frame.height == 72)
        try capture(clockPanel, name: "BetterApple-compact-clock.png")
        manager.update(clockID) { $0.apply(.desktopClock) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        manager.update(clockID) { $0.apply(.pureBlack) }
        assert(clockPanel.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        manager.editing = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        assert(clockPanel.contentView === clockHosting)
        assert(manager.widgets[0].surface == .card && manager.widgets[0].opacity == 1)
        manager.update(clockID) { $0.apply(.glass) }
        manager.update(clockID) { $0.apply(.desktopClock) }
        manager.editing = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        assert(clockPanel.contentView === clockHosting && clockPanel.frame.height == 250)
        manager.remove(id: clockID)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        if snapshotDirectory != nil {
            manager.system.start()
            manager.add(kind: .battery)
            let batteryID = manager.widgets[0].id
            manager.update(batteryID) { $0.apply(.statusBar) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let statusPanel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            try capture(statusPanel, name: "BetterApple-status-widget.png")
            manager.update(batteryID) { $0.apply(.pureBlack) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            try capture(statusPanel, name: "BetterApple-black-widget.png")
            manager.remove(id: batteryID)
            manager.system.stop()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        manager.hide()
        for _ in 0..<4 { manager.add(kind: .clock) }
        manager.widgets.indices.forEach { manager.widgets[$0].width = 800; manager.widgets[$0].height = 800 }
        let originalOrigins = manager.widgets.map { CGPoint(x: $0.x, y: $0.y) }
        manager.arrangeVisible()
        assert(manager.widgets.map { CGPoint(x: $0.x, y: $0.y) } == originalOrigins)
        assert(manager.layoutMessage?.contains("have not changed") == true)
        manager.setAllVisible(false)
        manager.flushPersistence()
        print("PASS: real widget show/fade/retarget/snap/removal, desktop/glass/black reversal retains hosting and dimensions, mounted SwiftUI and native note binding, no transient frame persistence, note hosting identity, rapid re-show isolation, overflow arrangement preserves layout.")
    }
}
