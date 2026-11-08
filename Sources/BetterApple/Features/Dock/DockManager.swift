import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, left, right
    var id: String { rawValue }
}

struct DockPreferences: Codable, Equatable {
    var enabled = false
    var iconSize: Double = 48
    var spacing: Double = 10
    var opacity: Double = 0.9
    var position: DockPosition = .bottom
    var autoHide = false
    var screenID: String = ""
    var applicationPaths: [String] = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Music.app"]
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
    @Published var preferences: DockPreferences { didSet { save(); refresh() } }
    @Published private(set) var applications: [DockApplication] = []
    @Published var hovering = false
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var hideWork: DispatchWorkItem?
    private var iconCache: [String: NSImage] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "dock.preferences"), let saved = try? JSONDecoder().decode(DockPreferences.self, from: data) {
            preferences = saved
        } else {
            var initial = DockPreferences()
            initial.applicationPaths = ["com.apple.finder", "com.apple.Safari", "com.apple.Music"].compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
            preferences = initial
        }
        preferences.iconSize = preferences.iconSize.isFinite ? min(80, max(24, preferences.iconSize)) : 48
        preferences.spacing = preferences.spacing.isFinite ? min(24, max(0, preferences.spacing)) : 10
        preferences.opacity = preferences.opacity.isFinite ? min(1, max(0.2, preferences.opacity)) : 0.9
        preferences.applicationPaths = Array(NSOrderedSet(array: preferences.applicationPaths).array.compactMap { $0 as? String }.prefix(50))
        preferences.applicationPaths = preferences.applicationPaths.map { path in
            if path == "/System/Applications/Finder.app" { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")?.path ?? path }
            if path == "/System/Applications/Safari.app" { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")?.path ?? path }
            return path
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reloadApplications() }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        reloadApplications()
    }

    func show() { preferences.enabled = true }
    func hide() { preferences.enabled = false }
    func refresh() {
        guard preferences.enabled else {
            hideWork?.cancel(); panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
            return
        }
        reloadApplications()
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.isReleasedWhenClosed = false
            panel = window
            window.contentView = NSHostingView(rootView: DockSurface(manager: self))
        }
        positionWindow()
        panel?.orderFrontRegardless()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "dock.preferences") }
    }

    private func reloadApplications() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
        applications = preferences.applicationPaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let icon = iconCache[path] ?? NSWorkspace.shared.icon(forFile: path)
            iconCache[path] = icon
            return DockApplication(url: url, name: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), icon: icon, running: running.contains(url.standardizedFileURL.path))
        }
    }

    private func positionWindow() {
        guard let panel, let screen = NSScreen.screens.first(where: { Self.screenID($0) == preferences.screenID }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = min(80, max(24, preferences.iconSize))
        let spacing = min(24, max(0, preferences.spacing))
        let count = Double(max(1, applications.count))
        let length = min((size + spacing) * count + 30, preferences.position == .bottom ? frame.width - 24 : frame.height - 24)
        let thickness = preferences.autoHide && !hovering ? 10 : size + 42
        let rect: NSRect
        switch preferences.position {
        case .bottom: rect = NSRect(x: frame.midX - length / 2, y: frame.minY + 8, width: length, height: thickness)
        case .left: rect = NSRect(x: frame.minX + 8, y: frame.midY - length / 2, width: thickness, height: length)
        case .right: rect = NSRect(x: frame.maxX - thickness - 8, y: frame.midY - length / 2, width: thickness, height: length)
        }
        panel.setFrame(rect, display: true)
    }

    func hover(_ entered: Bool) {
        hideWork?.cancel()
        if entered {
            hovering = true; positionWindow()
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hovering = false; self.positionWindow()
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
        }
    }

    func launch(_ app: DockApplication) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("BetterApple Dock: %@", error.localizedDescription) }
        }
    }

    func chooseApplications() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = true
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        guard picker.runModal() == .OK else { return }
        for url in picker.urls where !preferences.applicationPaths.contains(url.path) { preferences.applicationPaths.append(url.path) }
    }
    func remove(id: String) { preferences.applicationPaths.removeAll { $0 == id } }
    func move(from source: String, to destination: String) {
        guard source != destination, let from = preferences.applicationPaths.firstIndex(of: source), let to = preferences.applicationPaths.firstIndex(of: destination) else { return }
        var paths = preferences.applicationPaths
        let path = paths.remove(at: from)
        paths.insert(path, at: min(to, paths.count))
        preferences.applicationPaths = paths
    }
    static func screenID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        hideWork?.cancel()
    }
}

private struct DockSurface: View {
    @ObservedObject var manager: DockManager
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var vertical: Bool { manager.preferences.position != .bottom }
    var body: some View {
        Group {
            if manager.preferences.autoHide && !manager.hovering {
                Capsule().fill(.ultraThinMaterial).overlay(Capsule().stroke(.white.opacity(0.18)))
            } else {
                let layout = vertical ? AnyLayout(VStackLayout(spacing: manager.preferences.spacing)) : AnyLayout(HStackLayout(spacing: manager.preferences.spacing))
                ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                  layout {
                    ForEach(manager.applications) { app in
                        VStack(spacing: 3) {
                            Button { manager.launch(app) } label: {
                                Image(nsImage: app.icon).resizable().scaledToFit()
                                    .frame(width: manager.preferences.iconSize, height: manager.preferences.iconSize)
                                    .scaleEffect(hovered == app.id ? 1.16 : 1)
                            }
                            .buttonStyle(.plain).help(app.name).accessibilityLabel("Open \(app.name)")
                            .onHover { hovered = $0 ? app.id : nil }
                            .contextMenu { Button("Remove from BetterApple Dock", role: .destructive) { manager.remove(id: app.id) } }
                            .draggable(app.id)
                            .dropDestination(for: String.self) { items, _ in
                                guard let source = items.first, manager.preferences.applicationPaths.contains(source) else { return false }
                                manager.move(from: source, to: app.id); return true
                            }
                            Circle().fill(app.running ? Color.primary : .clear).frame(width: 4, height: 4)
                        }
                    }
                    if manager.applications.isEmpty {
                        Button { manager.chooseApplications() } label: { Image(systemName: "plus.app").font(.title) }.buttonStyle(.plain).help("Add applications")
                    }
                  }.padding(14)
                }
                .background(.ultraThinMaterial.opacity(manager.preferences.opacity), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.16)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { manager.hover($0) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
    }
}

struct DockSettingsView: View {
    @ObservedObject var manager: DockManager
    var body: some View {
        Form {
            Section("Independent Dock") {
                Toggle("Enable BetterApple Dock", isOn: $manager.preferences.enabled)
                Picker("Position", selection: $manager.preferences.position) { ForEach(DockPosition.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Display", selection: $manager.preferences.screenID) {
                    Text("Main display").tag("")
                    ForEach(NSScreen.screens, id: \.self) { screen in Text(screen.localizedName).tag(DockManager.screenID(screen)) }
                }
                LabeledContent("Icon size") { Slider(value: $manager.preferences.iconSize, in: 24...80, step: 2).frame(width: 180) }
                LabeledContent("Spacing") { Slider(value: $manager.preferences.spacing, in: 0...24, step: 1).frame(width: 180) }
                LabeledContent("Material opacity") { Slider(value: $manager.preferences.opacity, in: 0.2...1).frame(width: 180) }
                Toggle("Automatically hide", isOn: $manager.preferences.autoHide)
            }
            Section("Applications") {
                ForEach(manager.applications) { app in
                    HStack { Image(nsImage: app.icon).resizable().frame(width: 24, height: 24); Text(app.name); Spacer(); Button("Remove") { manager.remove(id: app.id) } }
                }
                Button("Add applications…") { manager.chooseApplications() }
                Text("Drag icons onto another icon to reorder. The macOS Dock remains independent.").font(.caption).foregroundStyle(.secondary)
                Button("Open macOS Dock settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!) }
            }
        }.formStyle(.grouped)
    }
}
