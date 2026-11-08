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
        assert(!manager.preferences.enabled)
        manager.preferences.applicationPaths = []
        assert(manager.applications.isEmpty)
        manager.preferences.applicationPaths = initialPaths
        assert(Set(manager.applications.map(\.id)) == Set(initialPaths))
        let disabledPreferences = manager.preferences
        let persistedBeforeSettings = defaults.data(forKey: "dock.preferences")
        manager.prepareSettings()
        assert(manager.preferences == disabledPreferences)
        assert(defaults.data(forKey: "dock.preferences") == persistedBeforeSettings)
        assert(!manager.applications.isEmpty && manager.applications.allSatisfy { !$0.name.isEmpty && $0.icon.size.width > 0 })
        assert(NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.isEmpty)
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
        print("PASS: legacy Dock JSON; validation bounds; disabled settings metadata stays current without windows or preference changes; native panels; per-screen hover; all-display panel count; running apps; hide cleanup; persisted appearance; deterministic presets.")
    }
}
