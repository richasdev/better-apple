import AppKit
import Foundation

@main
struct DockSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let oldData = Data("{\"iconSize\":40,\"applicationPaths\":[\"/System/Library/CoreServices/Finder.app\"]}".utf8)
        let legacy = try JSONDecoder().decode(DockPreferences.self, from: oldData)
        assert(legacy.presentation == .rail && legacy.enabledModules == [.apps] && legacy.moduleOrder == DockModule.allCases)
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
        // Explicit modular presets preserve the user's app list, note and feature state.
        manager.note = "A real local Dock note"
        let savedScreen = manager.preferences.screenID
        manager.applyLayoutPreset(.floating)
        assert(!manager.preferences.enabled && manager.preferences.presentation == .floating)
        assert(manager.preferences.applicationPaths == initialPaths && manager.note == "A real local Dock note")
        assert(manager.preferences.screenID == savedScreen && Set(manager.preferences.enabledModules) == Set(DockModule.allCases))
        manager.moveModule(.note, by: -1)
        assert(manager.preferences.moduleOrder.last == .battery)
        manager.setModule(.music, enabled: false)
        assert(!manager.preferences.enabledModules.contains(.music))
        manager.setModule(.music, enabled: true)
        manager.applyPureBlack()
        assert(manager.preferences.theme == .dark && manager.preferences.material == .solid && manager.preferences.opacity == 1)
        assert(!manager.preferences.enabled && manager.preferences.presentation == .floating && manager.note == "A real local Dock note")
        let modularRestored = DockManager(defaults: defaults)
        assert(modularRestored.preferences.presentation == .floating && modularRestored.preferences.moduleOrder == manager.preferences.moduleOrder)
        assert(modularRestored.preferences.enabledModules == manager.preferences.enabledModules && modularRestored.note == manager.note)
        var duplicateModules = manager.preferences
        duplicateModules.moduleOrder = [.timer, .timer]
        duplicateModules.enabledModules = [.note, .note]
        let repairedModules = try duplicateModules.validated()
        assert(repairedModules.enabledModules == [.note] && repairedModules.moduleOrder.first == .timer && Set(repairedModules.moduleOrder).count == DockModule.allCases.count)

        let timer = TimerService(defaults: defaults)
        let music = MusicService()
        let system = SystemStatusService()
        manager.sources = DockActivitySources(music: music, system: system, timer: timer)
        assert(manager.sources?.timer === timer && manager.sources?.music === music)
        assert(!music.isConnected) // Mounting a music tile must not request Automation.
        manager.preferences.animationDuration = 0
        manager.preferences.autoHide = false
        manager.preferences.allDisplays = false
        manager.preferences.showRunningApplications = false
        let display = NSScreen.main!
        manager.preferences.screenID = DockManager.screenID(display)
        manager.show()
        system.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        func capture(_ panel: NSWindow, name: String) throws {
            guard let view = panel.contentView else { fatalError("Dock content must be mounted") }
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Dock did not provide a native bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: "/tmp/" + name.replacingOccurrences(of: ".png", with: "-raw.png")))
            }
            let image = NSImage(size: NSSize(width: view.bounds.width + 40, height: view.bounds.height + 40))
            image.lockFocus()
            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            NSRect(origin: .zero, size: image.size).fill()
            let cached = NSImage(size: view.bounds.size)
            cached.addRepresentation(bitmap)
            cached.draw(in: NSRect(x: 20, y: 20, width: view.bounds.width, height: view.bounds.height), from: .zero, operation: .sourceOver, fraction: 1)
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode Dock bitmap") }
            try png.write(to: URL(fileURLWithPath: "/tmp/" + name))
        }
        for position in DockPosition.allCases {
            manager.preferences.position = position
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }!
            let metrics = DockContentMetrics(manager.preferences, applicationCount: manager.applications.count,
                                             reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            let vertical = position != .bottom
            let available = display.visibleFrame
            let axis = vertical ? available.height : available.width
            let cross = vertical ? available.width : available.height
            let actualAxis = vertical ? panel.frame.height : panel.frame.width
            let actualCross = vertical ? panel.frame.width : panel.frame.height
            assert(abs(actualAxis - min(metrics.length, axis - min(12, axis / 4) * 2)) < 1)
            assert(abs(actualCross - min(metrics.thickness, cross - min(8, cross / 4) * 2)) < 1)
            assert(available.contains(panel.frame))
            assert(panel.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            if position == .bottom {
                try capture(panel, name: "BetterApple-modular-dock.png")
                manager.preferences.presentation = .rail
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                try capture(panel, name: "BetterApple-modular-dock-rail.png")
                manager.preferences.presentation = .floating
            }
        }
        system.stop()
        let visibleModulePanels = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }
        print("Module demand diagnostics:", manager.activeModules.map(\.rawValue).sorted(), visibleModulePanels.map { "\($0.occlusionState.rawValue) / \($0.frame)" })
        fflush(stdout)
        let isActuallyVisible = visibleModulePanels.contains { $0.occlusionState.contains(.visible) }
        assert(manager.activeModules == (isActuallyVisible ? Set(DockModule.allCases) : []))
        manager.setModule(.battery, enabled: false)
        assert(!manager.activeModules.contains(.battery))
        assert(manager.activeModules == (isActuallyVisible ? Set(DockModule.allCases.filter { $0 != .battery }) : []))
        manager.preferences.autoHide = true
        assert(manager.activeModules.isEmpty)
        manager.hover(true, screenID: DockManager.screenID(display))
        let revealedVisible = NSApp.windows.contains { $0 is NSPanel && $0.isVisible && $0.occlusionState.contains(.visible) }
        assert(manager.activeModules.contains(.timer) == revealedVisible)
        manager.hide()
        assert(manager.activeModules.isEmpty && manager.note == "A real local Dock note")
        assert(!music.isConnected)
        print("PASS: modular rail/floating preferences, explicit presets preserve user data, pure black, module order/deduplication, note persistence, real shared sources, mixed-axis native bounds, explicit dark panel appearance, actual-occlusion/disabled/auto-hide demand and no implicit music authorization.")
        print("PASS: legacy Dock JSON; validation bounds; disabled settings metadata stays current without windows or preference changes; native panels; per-screen hover; all-display panel count; running apps; hide cleanup; persisted appearance; deterministic presets.")
    }
}
