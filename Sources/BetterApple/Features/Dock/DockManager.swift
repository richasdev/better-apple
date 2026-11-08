import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BetterAppleCore

private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct DockApplication: Identifiable {
    let url: URL
    let name: String
    let icon: NSImage
    let running: Bool
    var id: String { url.path }
}

@MainActor
final class DockManager: ObservableObject {
    @Published var preferences: DockPreferences { didSet { if preferences != oldValue { save(); refresh() } } }
    @Published private(set) var applications: [DockApplication] = []
    @Published private(set) var hoveringScreens: Set<String> = []
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private var destinations: [String: (panel: NSPanel, screen: NSScreen)] = [:]
    private var observers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var hideWork: [String: DispatchWorkItem] = [:]
    private var hoverRevisions: [String: UInt] = [:]
    private var iconCache: [String: NSImage] = [:]
    private var menuTracking = false
    var hovering: Bool { !hoveringScreens.isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "dock.preferences"), let saved = try? JSONDecoder().decode(DockPreferences.self, from: data).validated() {
            preferences = saved
        } else {
            var initial = DockPreferences()
            initial.applicationPaths = ["com.apple.finder", "com.apple.Safari", "com.apple.Music"].compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
            preferences = initial
        }
        preferences.applicationPaths = preferences.applicationPaths.map { path in
            if path == "/System/Applications/Finder.app" { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")?.path ?? path }
            if path == "/System/Applications/Safari.app" { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")?.path ?? path }
            return path
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            applicationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.preferences.enabled else { return }
                    self.reloadApplications(); self.positionWindows(animated: true)
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.menuTracking = true }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.menuTracking = false
                for (id, destination) in self.destinations { self.hover(destination.panel.frame.contains(NSEvent.mouseLocation), screenID: id) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? DockPanel else { return }
            Task { @MainActor [weak self, weak window] in
                guard let self, let window, let id = self.destinations.first(where: { $0.value.panel === window })?.key else { return }
                self.hover(window.frame.contains(NSEvent.mouseLocation), screenID: id)
            }
        })
        reloadApplications()
    }

    func show() { preferences.enabled = true }
    func hide() { preferences.enabled = false }
    func applyPreset(_ preset: AppearancePreset) {
        guard preset != .custom else { return }
        var next = preferences
        next.theme = .system; next.material = .glass; next.accent = .system
        next.iconSize = 48; next.spacing = 10; next.opacity = 0.9; next.cornerRadius = 22
        next.magnification = 1.16; next.animationDuration = 0.16; next.showLabels = false
        switch preset {
        case .minimal: next.iconSize = 36; next.spacing = 6; next.opacity = 0.85; next.magnification = 1; next.cornerRadius = 14
        case .glass: next.opacity = 0.65; next.cornerRadius = 28; next.magnification = 1.25
        case .compact: next.iconSize = 36; next.spacing = 6; next.cornerRadius = 16; next.magnification = 1.1
        case .default, .custom: break
        }
        preferences = next
    }
    func refresh() {
        guard preferences.enabled else { closePanels(); return }
        reloadApplications()
        let screens = preferences.allDisplays ? NSScreen.screens : [NSScreen.screens.first(where: { Self.screenID($0) == preferences.screenID }) ?? NSScreen.main].compactMap { $0 }
        let wanted = Set(screens.map(Self.screenID))
        for id in Array(destinations.keys) where !wanted.contains(id) { closePanel(id) }
        for screen in screens {
            let id = Self.screenID(screen)
            if destinations[id] == nil {
                let window = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
                window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
                window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .stationary]
                window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
                let hosting = NSHostingView(rootView: DockSurface(manager: self, screenID: id))
                // AppKit owns the reveal strip's explicit size. Retained hidden
                // icons must not impose their expanded minimum on the panel.
                hosting.sizingOptions = []
                window.contentView = hosting
                destinations[id] = (window, screen)
            } else if let panel = destinations[id]?.panel { destinations[id] = (panel, screen) }
        }
        positionWindows(animated: false)
        destinations.values.forEach { if !$0.panel.isVisible { $0.panel.orderFrontRegardless() } }
    }
    private func closePanel(_ id: String) {
        hideWork.removeValue(forKey: id)?.cancel(); hoveringScreens.remove(id)
        hoverRevisions.removeValue(forKey: id)
        guard let destination = destinations.removeValue(forKey: id) else { return }
        destination.panel.orderOut(nil); destination.panel.contentView = nil; destination.panel.close()
    }
    private func closePanels() { Array(destinations.keys).forEach(closePanel) }
    private func save() {
        if let valid = try? preferences.validated(), let data = try? JSONEncoder().encode(valid) { defaults.set(data, forKey: "dock.preferences") }
    }
    private func reloadApplications() {
        let regularApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let runningPaths = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap { $0.bundleURL?.standardizedFileURL.path })
        var paths = preferences.applicationPaths
        if preferences.showRunningApplications {
            let pinned = Set(paths)
            paths += regularApps.compactMap { $0.bundleURL?.path }.filter { !pinned.contains($0) }.sorted {
                FileManager.default.displayName(atPath: $0).localizedStandardCompare(FileManager.default.displayName(atPath: $1)) == .orderedAscending
            }
        }
        var seen = Set<String>()
        applications = paths.filter { seen.insert($0).inserted }.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let icon = iconCache[path] ?? NSWorkspace.shared.icon(forFile: path); iconCache[path] = icon
            return DockApplication(url: URL(fileURLWithPath: path), name: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), icon: icon, running: runningPaths.contains(URL(fileURLWithPath: path).standardizedFileURL.path))
        }
        let livePaths = Set(applications.map(\.id)); iconCache = iconCache.filter { livePaths.contains($0.key) }
    }
    private func positionWindows(animated: Bool) {
        let settings = (try? preferences.validated()) ?? DockPreferences()
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let metrics = DockLayoutMetrics(settings, reduceMotion: reduced)
        for (id, destination) in destinations {
            let frame = destination.screen.visibleFrame
            let vertical = settings.position != .bottom
            let axisLength = vertical ? frame.height : frame.width
            let crossLength = vertical ? frame.width : frame.height
            let axisMargin = min(12, axisLength / 4)
            let edgeMargin = min(8, crossLength / 4)
            let length = min(metrics.length(count: applications.count, vertical: vertical, spacing: settings.spacing), axisLength - axisMargin * 2)
            let requestedThickness = settings.autoHide && !hoveringScreens.contains(id) ? 10 : metrics.thickness(vertical: vertical)
            let thickness = min(requestedThickness, crossLength - edgeMargin * 2)
            let rect: NSRect
            switch settings.position {
            case .bottom: rect = NSRect(x: frame.midX - length / 2, y: frame.minY + edgeMargin, width: length, height: thickness)
            case .left: rect = NSRect(x: frame.minX + edgeMargin, y: frame.midY - length / 2, width: thickness, height: length)
            case .right: rect = NSRect(x: frame.maxX - thickness - edgeMargin, y: frame.midY - length / 2, width: thickness, height: length)
            }
            guard destination.panel.frame != rect else { continue }
            if animated, !reduced, settings.animationDuration > 0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = settings.animationDuration
                    context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: hoveringScreens.contains(id))
                    destination.panel.animator().setFrame(rect, display: true)
                }
            } else { destination.panel.setFrame(rect, display: true) }
        }
    }
    func hover(_ entered: Bool, screenID: String) {
        guard destinations[screenID] != nil else { return }
        let revision = (hoverRevisions[screenID] ?? 0) &+ 1
        hoverRevisions[screenID] = revision
        hideWork.removeValue(forKey: screenID)?.cancel()
        if entered {
            if hoveringScreens.insert(screenID).inserted { positionWindows(animated: true) }
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverRevisions[screenID] == revision else { return }
                self.hideWork.removeValue(forKey: screenID)
                guard let destination = self.destinations[screenID], !self.menuTracking,
                      !destination.panel.isKeyWindow,
                      destination.panel.childWindows?.contains(where: \.isVisible) != true,
                      !destination.panel.frame.contains(NSEvent.mouseLocation) else { return }
                if self.hoveringScreens.remove(screenID) != nil { self.positionWindows(animated: true) }
            }
            hideWork[screenID] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
        }
    }
    func launch(_ app: DockApplication) {
        errorMessage = nil
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.errorMessage = error.localizedDescription } }
        }
    }
    func reveal(_ app: DockApplication) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
    func canQuit(_ app: DockApplication) -> Bool { app.running && Bundle(url: app.url)?.bundleIdentifier != "com.apple.finder" }
    func quit(_ app: DockApplication) {
        guard canQuit(app) else { return }
        errorMessage = nil
        let matches = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
        let accepted = matches.map { $0.terminate() }
        if accepted.contains(false) { errorMessage = "\(app.name) did not accept the quit request. Finish any dialogs or quit it from its menu." }
    }
    func chooseApplications() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.applicationBundle]; picker.allowsMultipleSelection = true
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        guard picker.runModal() == .OK else { return }
        var paths = preferences.applicationPaths
        for url in picker.urls where !paths.contains(url.path) && paths.count < 100 { paths.append(url.path) }
        preferences.applicationPaths = paths
    }
    func pin(_ app: DockApplication) {
        guard preferences.applicationPaths.count < 100, !preferences.applicationPaths.contains(app.id) else { return }
        preferences.applicationPaths.append(app.id)
    }
    func remove(id: String) { preferences.applicationPaths.removeAll { $0 == id } }
    func move(from source: String, to destination: String) {
        guard source != destination, let from = preferences.applicationPaths.firstIndex(of: source), let to = preferences.applicationPaths.firstIndex(of: destination) else { return }
        var paths = preferences.applicationPaths; let path = paths.remove(at: from); paths.insert(path, at: min(to, paths.count)); preferences.applicationPaths = paths
    }
    static func screenID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""
    }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        applicationObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        hideWork.values.forEach { $0.cancel() }
    }
}
