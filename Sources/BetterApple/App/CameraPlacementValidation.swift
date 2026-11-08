#if DEBUG
import AppKit
import BetterAppleCore

@MainActor
enum CameraPlacementValidation {
    static func run(_ app: AppCoordinator, directory: URL) async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let suiteName = "app.betterapple.camera-migration.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let migration = AppModel(defaults: defaults)
        migration.settings.island.enabled = false
        migration.settings.island.hoverToExpand = false
        migration.settings.island.autoCloseDelay = 0
        migration.settings.island.expandedWidth = 512
        migration.settings.island.visual.accent = .purple
        migration.enableCameraExperienceIfNeeded(defaults: defaults)
        checks["camera migration enables requested hover without discarding appearance"] = migration.settings.island.placementMode == .camera && migration.settings.island.enabled && migration.settings.island.hoverToExpand && migration.settings.island.autoCloseDelay > 0 && migration.settings.island.expandedWidth == 512 && migration.settings.island.visual.accent == .purple
        migration.settings.island.placementMode = .floating
        migration.settings.island.hoverToExpand = false
        migration.enableCameraExperienceIfNeeded(defaults: defaults)
        checks["camera migration respects later user choice"] = migration.settings.island.placementMode == .floating && !migration.settings.island.hoverToExpand
        let invalidData = Data(#"{"schemaVersion":999}"#.utf8)
        defaults.removeObject(forKey: "island.cameraExperience.v1")
        defaults.set(invalidData, forKey: "BetterApple.settings.v1")
        let incompatible = AppModel(defaults: defaults)
        incompatible.enableCameraExperienceIfNeeded(defaults: defaults)
        checks["camera migration preserves incompatible stored data"] = defaults.data(forKey: "BetterApple.settings.v1") == invalidData && incompatible.persistenceError != nil && !defaults.bool(forKey: "island.cameraExperience.v1")
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        guard let screen else { throw CocoaError(.coderInvalidValue) }
        let metrics = CameraScreenMetrics(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top, auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea)
        app.model.settings.island.placementMode = .camera
        app.model.settings.island.allDisplays = false
        app.model.settings.island.hoverToExpand = true
        app.model.settings.island.autoCloseDelay = 0.08
        app.model.settings.island.visual.animationDuration = 0.18
        app.model.settings.island.visual.compactStatus = true
        app.island.collapse(); app.island.applySettings()
        try await Task.sleep(for: .milliseconds(260))
        guard let body = NSApp.windows.compactMap({ $0 as? IslandPanel }).first(where: \.isVisible) else { throw CocoaError(.coderInvalidValue) }
        func expected(_ expanded: Bool) -> IslandWindowLayout {
            CameraIslandGeometry.layout(screen: metrics, expanded: expanded,
                expandedWidth: app.model.settings.island.expandedWidth, expandedHeight: app.model.settings.island.expandedHeight)
        }
        let compact = expected(false)
        let actualCompact = body.frame
        let caps = NSApp.windows.compactMap { $0 as? CameraCapPanel }.filter(\.isVisible)
        checks["camera mode uses the correct screen and discreet compact body"] = matches(body.frame, compact.bodyFrame)
        checks["camera compact state never requests data polling"] = app.island.compactModule == nil && app.island.activeModule == nil
        checks["camera cap exists only for a measured cutout"] = caps.count == (compact.capFrame == nil ? 0 : 1)
        if let cap = caps.first, let frame = compact.capFrame {
            checks["camera cap is exact narrow non-key window"] = matches(cap.frame, frame) && !cap.canBecomeKey && cap.level == .statusBar && cap.frame.width <= compact.cameraWidth
        }
        app.island.handlePointer(true, panel: caps.first ?? body)
        try await Task.sleep(for: .milliseconds(260))
        let expanded = expected(true)
        let actualExpanded = body.frame
        checks["camera hover expands downward from a fixed top edge"] = app.island.state.expanded && matches(body.frame, expanded.bodyFrame) && abs(body.frame.maxY - compact.bodyFrame.maxY) < 1
        checks["camera hover never requests keyboard activation"] = app.island.state.focusRequest == 0 && !body.isKeyboardTarget
        checks["expanded camera controls stay outside camera and menu band"] = body.frame.maxY <= (expanded.hasNotch ? screen.frame.maxY - expanded.cameraHeight : screen.visibleFrame.maxY) + 0.01
        app.island.handlePointer(true, panel: body)
        if let cap = caps.first { app.island.handlePointer(false, panel: cap) }
        try await Task.sleep(for: .milliseconds(180))
        checks["crossing from camera cap to body keeps island open"] = app.island.state.expanded
        app.island.open()
        checks["clicking after camera hover keeps island open"] = app.island.state.expanded
        app.island.yieldKeyboardToSettings()
        app.island.handlePointer(false, panel: body)
        try await Task.sleep(for: .milliseconds(320))
        let pointerInside = ([body as NSWindow] + caps).contains { $0.isOnActiveSpace && $0.frame.contains(NSEvent.mouseLocation) }
        checks["camera exit respects pointer and closes automatically"] = pointerInside ? app.island.state.expanded : !app.island.state.expanded
        app.island.collapse()
        try await Task.sleep(for: .milliseconds(230))
        checks["camera body returns to the exact hidden size"] = matches(body.frame, compact.bodyFrame)
        let result: [String: Any] = ["hasNotch": expanded.hasNotch, "safeAreaTop": metrics.safeAreaTop,
            "screen": NSStringFromRect(screen.frame), "visible": NSStringFromRect(screen.visibleFrame),
            "actualCompact": NSStringFromRect(actualCompact), "actualExpanded": NSStringFromRect(actualExpanded),
            "actualReturned": NSStringFromRect(body.frame), "units": "points",
            "bodyCompact": NSStringFromRect(compact.bodyFrame), "bodyExpanded": NSStringFromRect(expanded.bodyFrame),
            "cap": compact.capFrame.map(NSStringFromRect) ?? "none", "hardwareCameraAccessRequested": false]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("camera-placement.json"))
        return checks
    }
    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}
#endif
