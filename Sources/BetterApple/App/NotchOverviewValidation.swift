#if DEBUG
import AppKit
import BetterAppleCore

@MainActor
enum NotchOverviewValidation {
    static func run(_ app: AppCoordinator, directory: URL) async throws -> [String: Bool] {
        let original = try app.configurationData()
        defer { app.music.disconnect(); app.island.collapse(); app.island.state.overview = false; try? app.applyConfigurationData(original) }
        var checks: [String: Bool] = [:]
        checks["overview validation never starts hardware listeners"] = !app.bluetooth.isRunning && !app.systemEvents.isRunning
        app.model.settings.island.enabled = true
        app.model.settings.island.placementMode = .camera
        app.model.settings.island.allDisplays = true
        app.model.settings.island.overviewOnHoverEnabled = true
        app.model.settings.island.dynamicHeightEnabled = true
        app.model.settings.island.autoCloseDelay = 0
        app.model.settings.island.visual.animationDuration = 0.16
        app.model.settings.island.modules = ModuleID.allCases
        app.model.settings.island.expandedWidth = 360
        app.island.collapse(); app.island.applySettings(); app.island.reveal()
        try await Task.sleep(for: .milliseconds(320))
        guard let body = NSApp.windows.compactMap({ $0 as? IslandPanel }).first(where: \.isVisible) else { throw CocoaError(.coderInvalidValue) }
        checks["notch opens horizontal overview without requesting keyboard"] = app.island.state.overview && app.island.state.expanded && app.island.state.focusRequest == 0 && !body.isKeyboardTarget && abs(body.frame.width - 560) < 1 && abs(body.frame.height - 140) < 1
        func capture(_ window: NSWindow, _ name: String) throws {
            guard let view = window.contentView else { throw CocoaError(.coderInvalidValue) }
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.coderInvalidValue) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        try capture(body, "notch-overview-empty")
        app.calculator.expression = "24 / 3"
        app.island.selectModule(.calculator)
        try await Task.sleep(for: .milliseconds(280))
        checks["overview tool action opens compact detailed editor"] = !app.island.state.overview && app.island.state.selected == .calculator && abs(body.frame.width - 360) < 1 && abs(body.frame.height - 195) < 1 && app.calculator.resultText == "8"
        app.island.showOverview()
        try await Task.sleep(for: .milliseconds(280))
        checks["back to overview preserves calculation and releases focus intent"] = app.island.state.overview && app.calculator.resultText == "8" && app.island.state.focusRequest == 0 && !body.isKeyboardTarget
        // A Debug-only local script fixture proves geometry/controls, never live player access.
        app.music.connect(to: OverviewMusicFixture())
        try await Task.sleep(for: .milliseconds(350))
        try capture(body, "notch-overview-playing-layout")
        checks["overview shares actual music service controls"] = app.music.isConnected && app.music.track?.title == "Notch overview validation"
        app.island.collapse()
        try await Task.sleep(for: .milliseconds(300))
        let caps = NSApp.windows.compactMap { $0 as? CameraCapPanel }.filter(\.isVisible)
        checks["collapsed connected music occupies notch wings"] = app.island.state.compactMusicTitle == "Notch overview validation" && !caps.isEmpty
        for (index, cap) in caps.enumerated() {
            try capture(cap, "notch-wings-\(index)")
            if let screen = cap.screen {
                let metrics = CameraScreenMetrics(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top,
                    auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea, menuBarHeight: NSStatusBar.system.thickness)
                let expected = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 560, expandedHeight: 140, compactExtension: 88)
                checks["music wings preserve top band on display \(index)"] = expected.capFrame.map { abs($0.width - cap.frame.width) < 1 && abs($0.height - cap.frame.height) < 1 && abs($0.maxY - cap.frame.maxY) < 1 } == true
            }
        }
        if let cap = caps.first {
            app.island.handlePointer(true, panel: cap)
            try await Task.sleep(for: .milliseconds(280))
            checks["hover opens overview rather than detailed module"] = app.island.state.overview && app.island.state.expanded && app.island.state.focusRequest == 0
            app.island.handlePointer(false, panel: cap)
        }
        for _ in 0..<4 { app.island.showOverview(); app.island.selectModule(.calculator); app.island.collapse() }
        app.island.showOverview()
        try await Task.sleep(for: .milliseconds(350))
        checks["overview interruption settles horizontal geometry"] = app.island.state.overview && abs(body.frame.width - 560) < 1 && abs(body.frame.height - 140) < 1
        app.island.collapse()
        app.model.settings.island.systemNoticesEnabled = true
        app.island.presentConnection(name: "Low Battery", symbol: "battery.25percent", connected: true, detail: "Mac battery", percentage: 20, systemEvent: true)
        try await Task.sleep(for: .milliseconds(280))
        checks["system event opens short notice without keyboard"] = app.island.state.connectionNoticeCompact && app.island.state.connectionNotice?.percentage == 20 && app.island.state.focusRequest == 0 && abs(body.frame.height - 60) < 1
        try capture(body, "notch-low-battery-notice")
        app.island.collapse()
        app.model.settings.island.systemNoticesEnabled = false
        app.island.presentConnection(name: "Ignored output", symbol: "hifispeaker", connected: true, systemEvent: true)
        checks["disabled system notices stay hidden"] = !app.island.state.expanded && app.island.state.connectionNotice == nil
        try JSONSerialization.data(withJSONObject: ["checks": checks, "livePlaybackAndHardwareEventsTested": false], options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("notch-overview.json"))
        return checks
    }
}

private struct OverviewMusicFixture: MusicPlayerAdapter {
    let id = "notch-overview-layout-validation"
    let title = "Layout test"
    var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "app.betterapple.desktop" }
    let snapshotScript = "return {\"Notch overview validation\", \"Local test fixture\", \"\", 180, 42, true, 50, \"\"}"
}
#endif
