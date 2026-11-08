import AppKit
import Foundation

@main
struct DockSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let oldData = Data("{\"iconSize\":40,\"applicationPaths\":[\"/System/Library/CoreServices/Finder.app\"]}".utf8)
        let legacy = try JSONDecoder().decode(DockPreferences.self, from: oldData)
        assert(legacy.iconSize == 40 && legacy.theme == .system && legacy.material == .glass && legacy.magnification == 1.16)
        var invalid = legacy
        invalid.magnification = .nan
        assert((try? invalid.validated()) == nil)
        invalid = legacy; invalid.applicationPaths = ["relative.app"]
        assert((try? invalid.validated()) == nil)
        var excessive = legacy; excessive.cornerRadius = 999; excessive.magnification = 20
        let clamped = try excessive.validated()
        assert(clamped.cornerRadius == 40 && clamped.magnification == 1.5)
        let suiteName = "app.betterapple.dock-personalization-smoke"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = DockManager(defaults: defaults)
        let initialPaths = manager.preferences.applicationPaths
        assert(!manager.applications.isEmpty)
        manager.preferences.cornerRadius = 31
        manager.preferences.theme = .dark
        manager.preferences.material = .solid
        manager.preferences.accent = .purple
        manager.preferences.magnification = 1.4
        manager.preferences.autoHide = true
        manager.show()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let panelCount = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.count
        assert(panelCount == 1)
        let screen = DockManager.screenID(NSScreen.main!)
        manager.hover(true, screenID: screen)
        assert(manager.hoveringScreens.contains(screen))
        manager.preferences.allDisplays = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        assert(NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.count == NSScreen.screens.count)
        manager.preferences.showRunningApplications = true
        assert(manager.applications.count >= initialPaths.count)
        manager.hide()
        assert(manager.hoveringScreens.isEmpty)
        assert(NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.isEmpty)
        let restored = DockManager(defaults: defaults)
        assert(restored.preferences.cornerRadius == 31 && restored.preferences.material == .solid && restored.preferences.theme == .dark && restored.preferences.accent == .purple)
        restored.applyPreset(.compact)
        assert(restored.preferences.iconSize == 36 && restored.preferences.spacing == 6 && restored.preferences.applicationPaths == initialPaths && restored.preferences.autoHide)
        restored.applyPreset(.default)
        assert(restored.preferences.iconSize == 48 && restored.preferences.opacity == 0.9 && restored.preferences.material == .glass && restored.preferences.magnification == 1.16)

        manager.preferences.animationDuration = 0
        manager.preferences.iconSize = 80
        manager.preferences.magnification = 1.5
        manager.preferences.showLabels = true
        manager.preferences.position = .left
        manager.preferences.allDisplays = false
        let targetScreen = NSScreen.screens[0]
        manager.preferences.screenID = DockManager.screenID(targetScreen)
        manager.show()
        if NSApp.windows.contains(where: { $0 is NSPanel && $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) }) {
            manager.preferences.position = .right
        }
        let id = DockManager.screenID(targetScreen)
        manager.hover(true, screenID: id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
        let metrics = DockLayoutMetrics(manager.preferences, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        assert(panel.canBecomeKey && !panel.canBecomeMain)
        assert(abs(panel.frame.width - metrics.thickness(vertical: true)) < 0.1)
        assert(panel.frame.minX >= targetScreen.visibleFrame.minX && panel.frame.maxX <= targetScreen.visibleFrame.maxX)
        manager.hover(false, screenID: id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        manager.hover(true, screenID: id)
        manager.hover(false, screenID: id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        assert(manager.hoveringScreens.contains(id))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        assert(!manager.hoveringScreens.contains(id))
        assert(panel.frame.width == 10)
        manager.hide()
        print("PASS: max magnification/labels panel bounds, keyboard-capable non-main panel, rapid hover cancellation and final hide deadline.")
        print("PASS: legacy Dock JSON; validation bounds; native panels; per-screen hover; all-display panel count; running apps; hide cleanup; persisted appearance; deterministic presets.")
    }
}
