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
    private var awaitingTermination = false
    private var terminationApproved = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if CommandLine.arguments.contains("--validate") {
            let defaults = UserDefaults(suiteName: "app.betterapple.validation")!
            defaults.removePersistentDomain(forName: "app.betterapple.validation")
            coordinator = AppCoordinator(defaults: defaults, bluetoothMonitoringAllowed: false, nativeDockChangesAllowed: false)
            coordinator?.start()
            if let coordinator { Task { await RuntimeValidation.run(coordinator) } }
            return
        }
        #endif
        coordinator = AppCoordinator()
        coordinator?.start()
    }
    func applicationWillTerminate(_ notification: Notification) { coordinator?.stop() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        guard !terminationApproved, coordinator.needsNativeDockRestoration else { return .terminateNow }
        guard !awaitingTermination else { return .terminateCancel }
        awaitingTermination = true
        Task { @MainActor in
            let restored = await coordinator.prepareForTermination()
            if !restored {
                let alert = NSAlert()
                alert.messageText = "The macOS Dock could not be restored"
                alert.informativeText = "Your original setting is saved. Check Automation permission or restore Automatically hide and show the Dock in System Settings → Desktop & Dock."
                alert.addButton(withTitle: "Cancel Quit")
                alert.addButton(withTitle: "Quit Anyway")
                if alert.runModal() == .alertFirstButtonReturn {
                    awaitingTermination = false
                    return
                }
            }
            terminationApproved = true
            awaitingTermination = false
            sender.terminate(nil)
        }
        // Do not hold AppKit's nested termination loop while a MainActor task
        // awaits System Events. Retry termination only after restoration finishes.
        return .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.showSettings(); return true
    }
}
