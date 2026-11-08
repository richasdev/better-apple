// Compile the core library first, then this harness (run from the repository root):
// /opt/homebrew/bin/rtk proxy mkdir -p /tmp/betterapple-productivity-check
// /opt/homebrew/bin/rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -emit-library -emit-module -module-name BetterAppleCore Sources/BetterAppleCore/*.swift -emit-module-path /tmp/betterapple-productivity-check/BetterAppleCore.swiftmodule -o /tmp/betterapple-productivity-check/libBetterAppleCore.dylib
// /opt/homebrew/bin/rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library -I /tmp/betterapple-productivity-check -L /tmp/betterapple-productivity-check -lBetterAppleCore -Xlinker -rpath -Xlinker /tmp/betterapple-productivity-check Sources/BetterApple/Services/*.swift Scripts/productivity-smoke.swift -o /tmp/betterapple-productivity-smoke
// /opt/homebrew/bin/rtk proxy /tmp/betterapple-productivity-smoke
// Uses isolated preferences; no clipboard writes, Automation, Calendar access or audible alert.
import AppKit
import BetterAppleCore

@main
struct ProductivitySmoke {
    @MainActor static func main() {
        _ = NSApplication.shared
        let name = "app.betterapple.productivity-smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let calculator = CalculatorService(defaults: defaults)
        calculator.expression = "0.1 + 0.2"
        assert(calculator.resultText == "0.3" && calculator.errorMessage == nil)
        calculator.commit()
        assert(calculator.history.isEmpty)
        calculator.historyEnabled = true
        calculator.commit(); calculator.commit()
        assert(calculator.history.count == 1)
        let restored = CalculatorService(defaults: defaults)
        assert(restored.historyEnabled && restored.history.count == 1)
        restored.use(restored.history[0])
        assert(restored.expression == "0.1 + 0.2" && restored.resultText == "0.3")
        restored.expression = "1 / 0"
        restored.commit()
        assert(restored.errorMessage != nil && restored.history.count == 1)
        restored.historyEnabled = false
        assert(restored.history.isEmpty && defaults.data(forKey: "calculator.history") == nil)

        let timer = TimerService(defaults: defaults)
        timer.label = String(repeating: "a", count: 100)
        assert(timer.label.count == 80)
        timer.completionSound = .silent
        timer.preferences.presetMinutes = [-1, 1, 1, 5, 2000]
        assert(timer.presetMinutes == [1, 5])
        timer.addPreset(minutes: 10)
        timer.removePreset(minutes: 1)
        assert(timer.presetMinutes == [5, 10])
        let restoredTimer = TimerService(defaults: defaults)
        assert(restoredTimer.label.count == 80 && restoredTimer.completionSound == .silent && restoredTimer.presetMinutes == [5, 10])
        timer.start(seconds: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        timer.pause()
        let paused = timer.remaining
        timer.extend(seconds: 60)
        assert(timer.isPaused && abs(timer.duration - 62) < 0.001 && abs(timer.remaining - paused - 60) < 0.001)
        assert((0...1).contains(timer.progress))
        timer.resume(); assert(timer.isRunning)
        timer.cancel(); assert(timer.progress == 0)
        timer.start(seconds: .infinity); assert(!timer.isRunning)
        timer.start(seconds: 0.05)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        assert(timer.didComplete && timer.progress == 1)
        timer.restart(); assert(timer.isRunning)
        timer.cancel()
        print("PASS: live calculator, bounded opt-in history persistence/privacy, timer preferences/normalization/extension/completion/restart.")
    }
}
