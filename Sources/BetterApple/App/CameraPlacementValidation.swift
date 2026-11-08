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
        checks["screen-edge cap exists on the selected display with or without a notch"] = caps.count == 1 && compact.capFrame != nil
        guard let cap = caps.first, let compactCap = compact.capFrame else { throw CocoaError(.coderInvalidValue) }
        let actualCapCompact = cap.frame
        checks["screen-edge cap matches the top-anchored non-key geometry"] = matches(cap.frame, compactCap) && !cap.canBecomeKey && cap.level == .statusBar && abs(cap.frame.maxY - screen.frame.maxY) < 1
        checks["compact cap and body share a center and continuous black overlap"] = abs(cap.frame.midX - body.frame.midX) < 1 && cap.frame.minY < body.frame.maxY && cap.frame.maxX >= body.frame.maxX && cap.frame.minX <= body.frame.minX
        let fullscreenOptIn = app.model.settings.island.showInFullScreen
        checks["screen-edge panels respect the explicit fullscreen option"] = cap.collectionBehavior.contains(.fullScreenAuxiliary) == fullscreenOptIn && body.collectionBehavior.contains(.fullScreenAuxiliary) == fullscreenOptIn
        app.island.handlePointer(true, panel: cap)
        try await Task.sleep(for: .milliseconds(260))
        let expanded = expected(true)
        let actualExpanded = body.frame
        let actualCapExpanded = cap.frame
        checks["camera hover expands downward from a fixed top edge"] = app.island.state.expanded && matches(body.frame, expanded.bodyFrame) && abs(body.frame.maxY - compact.bodyFrame.maxY) < 1
        checks["expanded cap widens with the body while remaining flush to the screen"] = expanded.capFrame.map { matches(cap.frame, $0) } == true && cap.frame.width > actualCapCompact.width && abs(cap.frame.maxY - screen.frame.maxY) < 1 && abs(cap.frame.midX - body.frame.midX) < 1
        checks["expanded cap and body keep continuous overlapping surfaces"] = cap.frame.minY < body.frame.maxY && cap.frame.maxX >= body.frame.maxX && cap.frame.minX <= body.frame.minX
        checks["camera hover never requests keyboard activation"] = app.island.state.focusRequest == 0 && !body.isKeyboardTarget
        checks["expanded camera controls stay outside camera and menu band"] = body.frame.maxY <= screen.visibleFrame.maxY + 0.01 && body.frame.maxY <= screen.frame.maxY - metrics.safeAreaTop + 0.01
        app.island.handlePointer(true, panel: body)
        app.island.handlePointer(false, panel: cap)
        try await Task.sleep(for: .milliseconds(180))
        checks["crossing from camera cap to body keeps island open"] = app.island.state.expanded
        app.island.handlePointer(true, panel: cap)
        app.island.handlePointer(false, panel: body)
        try await Task.sleep(for: .milliseconds(180))
        checks["crossing from body back to the cap keeps island open"] = app.island.state.expanded
        app.island.open()
        checks["clicking after camera hover keeps island open"] = app.island.state.expanded
        app.island.yieldKeyboardToSettings()
        app.island.handlePointer(false, panel: cap)
        try await Task.sleep(for: .milliseconds(320))
        let pointerInside = [body as NSWindow, cap].contains { $0.isOnActiveSpace && $0.frame.contains(NSEvent.mouseLocation) }
        checks["camera exit respects pointer and closes automatically"] = pointerInside ? app.island.state.expanded : !app.island.state.expanded
        app.island.collapse()
        try await Task.sleep(for: .milliseconds(230))
        checks["camera body and cap return to their exact hidden sizes"] = matches(body.frame, compact.bodyFrame) && matches(cap.frame, compactCap)

        let originalWidth = app.model.settings.island.expandedWidth
        app.model.settings.island.autoCloseDelay = 0
        for _ in 0..<5 {
            app.island.state.expanded = true
            try await Task.sleep(for: .milliseconds(20))
            app.island.collapse()
            try await Task.sleep(for: .milliseconds(20))
        }
        app.island.state.expanded = true
        try await Task.sleep(for: .milliseconds(20))
        app.model.settings.island.expandedWidth = originalWidth == 512 ? 552 : 512
        app.island.applySettings()
        try await Task.sleep(for: .milliseconds(350))
        let editedExpanded = expected(true)
        let actualEditedExpanded = body.frame
        let actualEditedCap = cap.frame
        checks["rapid reversal and width edits preserve both camera panel identities"] = NSApp.windows.contains { $0 === body && $0.isVisible } && NSApp.windows.contains { $0 === cap && $0.isVisible }
        checks["rapid reversal and width edits settle exact expanded body and cap"] = app.island.state.expanded && matches(body.frame, editedExpanded.bodyFrame) && editedExpanded.capFrame.map { matches(cap.frame, $0) } == true
        app.island.collapse()
        try await Task.sleep(for: .milliseconds(260))
        checks["rapid camera reversal returns both panels to exact compact geometry"] = !app.island.state.expanded && matches(body.frame, compact.bodyFrame) && matches(cap.frame, compactCap)
        let result: [String: Any] = ["hasNotch": expanded.hasNotch, "safeAreaTop": metrics.safeAreaTop,
            "screen": NSStringFromRect(screen.frame), "visible": NSStringFromRect(screen.visibleFrame),
            "actualCompact": NSStringFromRect(actualCompact), "actualExpanded": NSStringFromRect(actualExpanded),
            "actualReturned": NSStringFromRect(body.frame), "actualCapCompact": NSStringFromRect(actualCapCompact),
            "actualCapExpanded": NSStringFromRect(actualCapExpanded), "actualCapReturned": NSStringFromRect(cap.frame),
            "actualEditedExpanded": NSStringFromRect(actualEditedExpanded), "actualEditedCap": NSStringFromRect(actualEditedCap),
            "units": "points", "coordinateSpace": "global screen coordinates",
            "bodyCompact": NSStringFromRect(compact.bodyFrame), "bodyExpanded": NSStringFromRect(expanded.bodyFrame),
            "capCompact": NSStringFromRect(compactCap), "capExpanded": expanded.capFrame.map(NSStringFromRect) ?? "none",
            "fullscreenOptIn": fullscreenOptIn, "hardwareCameraAccessRequested": false]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("camera-placement.json"))
        app.model.settings.island.expandedWidth = originalWidth
        app.model.settings.island.allDisplays = true
        app.island.applySettings()
        try await Task.sleep(for: .milliseconds(160))
        let displayBodies = NSApp.windows.compactMap { $0 as? IslandPanel }.filter(\.isVisible)
        let displayCaps = NSApp.windows.compactMap { $0 as? CameraCapPanel }.filter(\.isVisible)
        checks["every-display Island creates one body on each connected screen"] = displayBodies.count == NSScreen.screens.count && NSScreen.screens.allSatisfy { screen in
            let metrics = CameraScreenMetrics(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top, auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea)
            let frame = CameraIslandGeometry.layout(screen: metrics, expanded: false,
                expandedWidth: app.model.settings.island.expandedWidth, expandedHeight: app.model.settings.island.expandedHeight).bodyFrame
            return displayBodies.contains { matches($0.frame, frame) }
        }
        checks["every display has a flush-top cap including screens without notches"] = displayCaps.count == NSScreen.screens.count && NSScreen.screens.allSatisfy { screen in
            let metrics = CameraScreenMetrics(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top, auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea)
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: false,
                expandedWidth: app.model.settings.island.expandedWidth, expandedHeight: app.model.settings.island.expandedHeight)
            return layout.capFrame.map { frame in displayCaps.contains { matches($0.frame, frame) && abs($0.frame.maxY - screen.frame.maxY) < 1 } } == true
        }
        if let first = displayBodies.first {
            app.island.handlePointer(true, panel: first)
            try await Task.sleep(for: .milliseconds(260))
            checks["every-display Island shares expansion across connected screens"] = app.island.state.expanded && NSScreen.screens.allSatisfy { screen in
                let metrics = CameraScreenMetrics(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                    safeAreaTop: screen.safeAreaInsets.top, auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea)
                let layout = CameraIslandGeometry.layout(screen: metrics, expanded: true,
                    expandedWidth: app.model.settings.island.expandedWidth, expandedHeight: app.model.settings.island.expandedHeight)
                return displayBodies.contains { matches($0.frame, layout.bodyFrame) } && layout.capFrame.map { frame in displayCaps.contains { matches($0.frame, frame) } } == true
            }
            app.island.handlePointer(false, panel: first)
        }
        app.island.collapse()
        app.model.settings.island.allDisplays = false
        app.island.applySettings()
        return checks
    }
    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}
#endif
