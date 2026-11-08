// Compile from the repository root:
// /opt/homebrew/bin/rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library Sources/BetterApple/Services/*.swift Scripts/service-smoke.swift -o /tmp/betterapple-service-smoke
// /opt/homebrew/bin/rtk proxy /tmp/betterapple-service-smoke
// No Calendar/Automation prompts, playback changes, or volume writes occur.
import AppKit
import Foundation

private struct AdditionalPlayerAdapter: MusicPlayerAdapter {
    let id = "smoke-player"
    let title = "Smoke Player"
    let bundleIdentifier = "app.betterapple.smoke.notinstalled"
    let snapshotScript = "return {\"\", \"\", \"\", 0, 0, false, 50, \"\"}"
}

@main
struct ServiceSmoke {
    @MainActor static func main() {
        _ = NSApplication.shared
        let timer = TimerService()
        timer.setVisible(true)
        timer.start(seconds: 10)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        timer.pause()
        assert(timer.isPaused && !timer.isRunning)
        assert(timer.remaining > 9 && timer.remaining < 10)
        let paused = timer.remaining
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        assert(timer.remaining == paused)
        timer.resume()
        assert(timer.isRunning && !timer.isPaused)
        timer.cancel()
        assert(!timer.isRunning && !timer.isPaused && timer.remaining == 0)
        timer.start(seconds: .nan)
        assert(!timer.isRunning)
        let music = MusicService()
        music.start()
        assert(!music.isConnected && music.track == nil && music.errorMessage == nil)
        music.stop()
        music.registerAdapter(AdditionalPlayerAdapter())
        assert(music.availablePlayers.count == 3)
        assert(music.availablePlayers.contains { $0.id == "smoke-player" })
        music.connect(to: AdditionalPlayerAdapter())
        assert(music.selectedPlayer.id == "smoke-player")
        assert(!music.isConnected && music.errorMessage != nil)
        music.disconnect()
        let suite = "app.betterapple.shortcut-smoke." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let shortcut = GlobalShortcutService(defaults: preferences)
        assert(!shortcut.enabled && !shortcut.isRegistered && shortcut.errorMessage == nil)
        shortcut.key = .i
        shortcut.modifiers = .controlShift
        shortcut.enabled = true
        assert(shortcut.isRegistered || shortcut.errorMessage != nil)
        if shortcut.isRegistered {
            let duplicate = GlobalShortcutService(defaults: preferences)
            assert(!duplicate.isRegistered && duplicate.errorMessage != nil)
            shortcut.enabled = false
            duplicate.retryRegistration()
            assert(duplicate.isRegistered && duplicate.errorMessage == nil)
            duplicate.enabled = false
        } else {
            print("Shortcut registration unavailable on this host: \(shortcut.errorMessage ?? "unknown")")
            shortcut.enabled = false
        }
        assert(!shortcut.isRegistered)
        let restored = GlobalShortcutService(defaults: preferences)
        assert(!restored.enabled && restored.key == .i && restored.modifiers == .controlShift)
        restored.stop()
        let system = SystemStatusService()
        system.start()
        RunLoop.main.run(until: Date().addingTimeInterval(3.3))
        assert((0...1).contains(system.cpuUsage))
        assert(system.memoryUsedBytes > 0 && system.memoryUsedBytes <= system.memoryTotalBytes)
        if let battery = system.batteryLevel { assert((0...1).contains(battery)) }
        if let volume = system.outputVolume { assert((0...1).contains(volume)) }
        assert(system.networkBytesPerSecond >= 0)
        print("PASS: Timer start/pause/resume/cancel/NaN guard; Music no startup connection and custom adapter registration/selection; shortcut registration/conflict/teardown/preferences; live public system readings.")
        print("Observed CPU=\(system.cpuUsage), memory=\(system.memoryUsedBytes)/\(system.memoryTotalBytes), battery=\(String(describing: system.batteryLevel)), outputVolume=\(String(describing: system.outputVolume)), network=\(system.networkBytesPerSecond)")
        system.stop()
        let before = system.cpuUsage
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        assert(system.cpuUsage == before)
    }
}
