#if DEBUG
import AppKit
import BetterAppleCore

@MainActor
enum ConnectionNoticeValidation {
    static func run(_ app: AppCoordinator, directory: URL) async throws -> [String: Bool] {
        let original = try app.configurationData()
        defer { app.music.disconnect(); app.island.collapse(); try? app.applyConfigurationData(original) }
        var checks: [String: Bool] = [:]
        checks["Bluetooth validation never starts hardware monitoring"] = !app.bluetooth.isRunning
        app.model.settings.island.enabled = true
        app.model.settings.island.connectionNotificationsEnabled = true
        app.model.settings.island.placementMode = .camera
        app.model.settings.island.defaultModule = .calculator
        app.model.settings.island.dynamicHeightEnabled = true
        app.model.settings.island.expandedWidth = 360
        app.model.settings.island.autoCloseDelay = 0.08
        app.model.settings.island.visual.animationDuration = 0.18
        app.island.collapse(); app.island.applySettings()
        try await Task.sleep(for: .milliseconds(230))
        app.island.presentConnection(name: "AirPods Pro · validation", symbol: "airpodspro", connected: true)
        try await Task.sleep(for: .milliseconds(300))
        guard let body = NSApp.windows.compactMap({ $0 as? IslandPanel }).first(where: \.isVisible) else { throw CocoaError(.coderInvalidValue) }
        checks["connection event opens a compact notice without keyboard activation"] = app.island.state.expanded && app.island.state.connectionNoticeCompact && app.island.state.connectionNotice?.connected == true && app.island.state.focusRequest == 0 && !body.isKeyboardTarget && abs(body.frame.height - 92) < 1
        checks["connection-only notice does not activate a module service"] = app.island.activeModule == nil
        app.calculator.expression = "12 + 3"
        app.island.open()
        try await Task.sleep(for: .milliseconds(260))
        checks["clicking connection notice opens normal tools"] = app.island.state.connectionNotice == nil && !app.island.state.connectionNoticeCompact && app.island.state.expanded && body.isKeyboardTarget
        checks["calculator fits its active content instead of leaving a tall empty panel"] = abs(body.frame.height - min(195, app.model.settings.island.expandedHeight)) < 1
        checks["black Island uses native dark appearance"] = body.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        func editor(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let field = body.contentView.flatMap(editor)
        var color: NSColor?
        if let field {
            field.effectiveAppearance.performAsCurrentDrawingAppearance {
                color = (field.textColor ?? NSColor.controlTextColor).usingColorSpace(.sRGB)
            }
        }
        checks["native calculator text is light on the black surface"] = color.map { $0.redComponent + $0.greenComponent + $0.blueComponent > 2.1 } == true
        if let view = body.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("black-island-calculator.png"))
        }
        app.island.presentConnection(name: "Headphones · validation", symbol: "headphones", connected: false)
        try await Task.sleep(for: .milliseconds(260))
        checks["connection while editing keeps full tools and calculator content"] = !app.island.state.connectionNoticeCompact && app.calculator.expression == "12 + 3" && body.contentView.flatMap(editor) === field && abs(body.frame.height - min(265, app.model.settings.island.expandedHeight)) < 1
        app.island.open() // dismisses the inline event, retaining normal tools
        try await Task.sleep(for: .milliseconds(220))
        if let editor = body.firstResponder as? NSTextView, editor.isFieldEditor {
            app.island.handlePointer(true, panel: body)
            editor.setMarkedText("24", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            app.island.handlePointer(false, panel: body)
            try await Task.sleep(for: .milliseconds(160))
            checks["Island preserves active marked input after pointer exit"] = editor.hasMarkedText() && app.island.state.expanded
            editor.insertText("15", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            try await Task.sleep(for: .milliseconds(370))
            let surfacePointer = NSApp.windows.contains { $0.isVisible && ($0 is IslandPanel || $0 is CameraCapPanel) && $0.isOnActiveSpace && $0.frame.contains(NSEvent.mouseLocation) }
            checks["Island resumes pointer-exit collapse after marked input commit"] = !editor.hasMarkedText() && (surfacePointer ? app.island.state.expanded : !app.island.state.expanded)
            app.island.open()
            try await Task.sleep(for: .milliseconds(240))
        }
        app.island.handlePointer(true, panel: body)
        app.island.handlePointer(false, panel: body)
        try await Task.sleep(for: .milliseconds(370))
        let surfaces = NSApp.windows.filter { $0.isVisible && ($0 is IslandPanel || $0 is CameraCapPanel) }
        let pointerInside = surfaces.contains { $0.isOnActiveSpace && $0.frame.contains(NSEvent.mouseLocation) }
        checks["pointer exit collapses calculator despite ordinary editor focus"] = pointerInside ? app.island.state.expanded : !app.island.state.expanded
        app.island.collapse()
        app.island.presentConnection(name: "AirPods · validation", symbol: "airpods", connected: true)
        try await Task.sleep(for: .milliseconds(60))
        app.island.presentConnection(name: "AirPods · validation", symbol: "airpods", connected: false)
        checks["repeated connection event replaces the notice with latest status"] = app.island.state.connectionNotice?.connected == false
        try await Task.sleep(for: .milliseconds(4300))
        checks["connection notice dismisses on its finite deadline"] = app.island.state.connectionNotice == nil
        app.island.collapse()
        app.model.settings.island.connectionNotificationsEnabled = false
        app.island.applySettings()
        app.island.presentConnection(name: "Ignored validation", symbol: "headphones", connected: true)
        checks["disabled Bluetooth notices never open the Island"] = app.island.state.connectionNotice == nil && !app.island.state.expanded
        app.model.settings.island.autoCloseDelay = 0
        app.model.settings.island.expandedWidth = 360
        app.island.state.selected = .music
        app.island.open()
        try await Task.sleep(for: .milliseconds(280))
        checks["disconnected music opens at compact content height"] = abs(body.frame.height - 150) < 1 && abs(body.frame.width - 360) < 1 && !app.music.isConnected
        if let view = body.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("compact-island-music.png"))
        }
        app.model.settings.island.expandedWidth = 300
        app.island.applySettings()
        try await Task.sleep(for: .milliseconds(280))
        checks["compact music preserves minimum configured width"] = abs(body.frame.width - 300) < 1 && abs(body.frame.height - 150) < 1
        // A local script-only fixture exercises actual connected controls without
        // authorizing a player or touching anyone's playback. Never registered in Release.
        app.music.connect(to: CompactMusicLayoutFixture())
        try await Task.sleep(for: .milliseconds(350))
        checks["connected music fits compact layout at minimum width"] = app.music.isConnected && app.music.track?.title == "Compact layout validation" && abs(body.frame.width - 300) < 1 && abs(body.frame.height - 170) < 1
        if let view = body.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("compact-music-controls.png"))
        }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "hardwareBluetoothTested": false], options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("connection-notice.json"))
        return checks
    }
}

private struct CompactMusicLayoutFixture: MusicPlayerAdapter {
    let id = "compact-layout-validation"
    let title = "Layout test"
    var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "app.betterapple.desktop" }
    let snapshotScript = "return {\"Compact layout validation\", \"Test fixture\", \"\", 180, 42, false, 50, \"\"}"
}
#endif
