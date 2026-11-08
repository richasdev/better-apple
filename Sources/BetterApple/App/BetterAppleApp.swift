import SwiftUI
import AppKit

@main
struct BetterAppleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if CommandLine.arguments.contains("--validate") {
            let defaults = UserDefaults(suiteName: "app.betterapple.validation")!
            defaults.removePersistentDomain(forName: "app.betterapple.validation")
            coordinator = AppCoordinator(defaults: defaults)
            coordinator?.start()
            if let coordinator { Task { await RuntimeValidation.run(coordinator) } }
            return
        }
        #endif
        coordinator = AppCoordinator()
        coordinator?.start()
    }
    func applicationWillTerminate(_ notification: Notification) { coordinator?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.showSettings(); return true
    }
}
