#if DEBUG
import AppKit
import BetterAppleCore

@MainActor
enum InteractionValidation {
    /// A finite, repeatable workload for Instruments. It changes only isolated Debug preferences.
    static func profileMotion(_ app: AppCoordinator) async throws {
        app.model.settings.island.visual.animationDuration = 0.24
        app.model.settings.island.autoCloseDelay = 0
        app.model.settings.island.hoverToExpand = false
        app.island.applySettings()
        for _ in 0..<20 {
            app.island.state.selected = .calculator
            app.island.state.expanded = true
            try await Task.sleep(for: .milliseconds(320))
            app.island.state.selected = .timer
            try await Task.sleep(for: .milliseconds(160))
            app.island.collapse()
            try await Task.sleep(for: .milliseconds(260))
        }
    }
    static func run(_ app: AppCoordinator, directory: URL) async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        var samples: [[String: Any]] = []
        var unverified: [String] = []
        app.timer.cancel()
        app.widgets.editing = false
        app.model.settings.island.showInFullScreen = true
        app.model.settings.island.hoverToExpand = true
        app.model.settings.island.autoCloseDelay = 0.08
        app.model.settings.island.visual.animationDuration = 0.18
        app.island.applySettings(); app.island.collapse()
        try await Task.sleep(for: .milliseconds(250))
        guard let panel = NSApp.windows.compactMap({ $0 as? IslandPanel }).first(where: \.isVisible) else { throw CocoaError(.coderInvalidValue) }
        let previousKey = NSApp.keyWindow
        app.island.handlePointer(true, panel: panel)
        try await Task.sleep(for: .milliseconds(35))
        checks["hover expansion never requests keyboard activation"] = app.island.state.expanded && app.island.state.focusRequest == 0 && !panel.isKeyboardTarget && !panel.isKeyWindow && NSApp.keyWindow === previousKey
        app.island.handlePointer(false, panel: panel)
        app.island.togglePin()
        try await Task.sleep(for: .milliseconds(160))
        checks["pin protects against pending auto-close"] = app.island.state.expanded && app.island.state.pinned
        app.island.togglePin()
        try await Task.sleep(for: .milliseconds(300))
        let pointerInside = panel.isOnActiveSpace && panel.frame.contains(NSEvent.mouseLocation)
        checks["auto-close respects actual pointer"] = pointerInside ? app.island.state.expanded : !app.island.state.expanded

        app.model.settings.island.hoverToExpand = false
        app.model.settings.island.autoCloseDelay = 0
        app.island.applySettings(); app.island.collapse()
        try await Task.sleep(for: .milliseconds(220))
        app.calculator.expression = "2 + 2"
        app.island.state.selected = .calculator
        app.island.toggle()
        try await Task.sleep(for: .milliseconds(35))
        let earlyEditor = panel.firstResponder as? NSTextView
        checks["explicit open prepares native editor during expansion"] = panel.isKeyboardTarget && earlyEditor?.isFieldEditor == true
        if !panel.isKeyWindow { unverified.append("macOS did not grant foreground key activation; prepared editor and binding are tested without claiming global typing delivery") }
        if earlyEditor?.isFieldEditor == true {
            earlyEditor?.insertText("7", replacementRange: NSRange(location: 0, length: (earlyEditor!.string as NSString).length))
        }
        try await Task.sleep(for: .milliseconds(20))
        checks["early native editor input reaches calculator"] = app.calculator.expression == "7" && app.calculator.resultText == "7"
        samples.append(["event": "explicit_open_55ms", "width": panel.frame.width, "height": panel.frame.height,
                        "contentVisible": app.island.state.expandedContentVisible, "keyboardEditor": earlyEditor?.isFieldEditor == true, "isKey": panel.isKeyWindow, "request": app.island.state.focusRequest, "appActive": NSApp.isActive, "activationPolicy": NSApp.activationPolicy().rawValue, "responder": panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"])
        for module in [ModuleID.timer, .calculator, .timer, .calculator] {
            app.island.selectModule(module)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(250))
        checks["rapid module reversal prepares correct native editor"] = panel.isKeyboardTarget && (panel.firstResponder as? NSTextView)?.string == app.calculator.expression
        app.island.togglePin()
        app.showSettings()
        try await Task.sleep(for: .milliseconds(70))
        let settings = NSApp.keyWindow
        samples.append(["event": "settings_before_default", "title": settings?.title ?? "nil", "appActive": NSApp.isActive, "activationPolicy": NSApp.activationPolicy().rawValue, "keyIsIsland": panel.isKeyWindow, "request": app.island.state.focusRequest])
        app.model.settings.island.defaultModule = .timer
        app.island.applySettings()
        try await Task.sleep(for: .milliseconds(250))
        samples.append(["event": "settings_after_default", "title": NSApp.keyWindow?.title ?? "nil", "appActive": NSApp.isActive, "activationPolicy": NSApp.activationPolicy().rawValue, "keyIsIsland": panel.isKeyWindow, "request": app.island.state.focusRequest])
        checks["settings request clears stale island focus intent"] = !panel.isKeyboardTarget && app.island.state.focusRequest == 0
        if settings?.title == "BetterApple" {
            checks["default-module changes preserve granted settings focus"] = NSApp.keyWindow === settings && !panel.isKeyWindow
        } else { unverified.append("macOS did not grant Settings key activation; focus retention relative to other applications is not certified") }
        app.model.settings.island.defaultModule = .calculator
        app.island.applySettings(); app.island.collapse()
        try await Task.sleep(for: .milliseconds(250))
        for _ in 0..<8 { app.island.toggle(); try await Task.sleep(for: .milliseconds(15)) }
        app.island.toggle()
        try await Task.sleep(for: .milliseconds(15))
        app.island.collapse()
        app.model.settings.island.width = 322
        app.island.applySettings()
        try await Task.sleep(for: .milliseconds(350))
        checks["rapid reversal and preference edit settle exact compact geometry"] = !app.island.state.expanded && !app.island.state.expandedContentVisible && app.island.state.compactContentVisible && abs(panel.frame.width - 322) < 1 && abs(panel.frame.height - app.model.settings.island.height) < 1 && !panel.isKeyWindow
        samples.append(["event": "rapid_reverse_settled", "width": panel.frame.width, "height": panel.frame.height,
                        "expanded": app.island.state.expanded, "compactVisible": app.island.state.compactContentVisible])
        app.model.settings.island.visual.animationDuration = 0
        app.island.applySettings(); app.island.toggle()
        try await Task.sleep(for: .milliseconds(35))
        checks["disabled motion has no delayed visible content"] = app.island.state.expandedContentVisible && !app.island.state.compactContentVisible && abs(panel.frame.width - app.model.settings.island.expandedWidth) < 1
        app.island.collapse()
        try await Task.sleep(for: .milliseconds(35))
        checks["disabled motion collapses without lingering content"] = !app.island.state.expandedContentVisible && app.island.state.compactContentVisible && !panel.canBecomeKey && !panel.isKeyboardTarget

        checks["timer draft validates actual text including locale"] = ["", "garbage", "NaN", "0", "-1", "1e99"].allSatisfy { TimerDraftValidation.minutes($0) == nil } && TimerDraftValidation.minutes("1.5", locale: Locale(identifier: "en_US")) == 1.5 && TimerDraftValidation.minutes("1,5", locale: Locale(identifier: "pt_BR")) == 1.5 && TimerDraftValidation.presetMinutes("1.5") == nil
        app.showSettings()
        try await Task.sleep(for: .milliseconds(40))
        let keyBeforeNotice = NSApp.keyWindow
        app.notices.show("Native interaction validation", openSettings: {})
        try await Task.sleep(for: .milliseconds(220))
        let notice = NSApp.windows.compactMap { $0 as? SurfaceNoticePanel }.first(where: \.isVisible)
        checks["feedback notice permits intentional focus without taking it"] = notice?.canBecomeKey == true && notice?.canBecomeMain == false && notice?.isKeyWindow == false && NSApp.keyWindow === keyBeforeNotice
        app.notices.dismiss(animated: false)
        checks["feedback notice teardown removes its window"] = !NSApp.windows.contains { $0 is SurfaceNoticePanel && $0.isVisible }
        app.showDockSettings()
        checks["dock error settings action routes to dock"] = app.lastSettingsSection == "Dock"
        let context: [String: Any] = ["activationPolicy": NSApp.activationPolicy().rawValue, "appActive": NSApp.isActive, "unverified": unverified]
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("interaction-context.json"))
        try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("motion-samples.json"))
        return checks
    }
}
#endif
