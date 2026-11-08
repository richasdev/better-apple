import SwiftUI
import AppKit
import ServiceManagement
import BetterAppleCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", island = "Dynamic Island", dock = "Dock", widgets = "Widgets", appearance = "Appearance", shortcuts = "Shortcuts", performance = "Performance", permissions = "Permissions", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .island: return "capsule"
        case .dock: return "dock.rectangle"
        case .widgets: return "square.grid.2x2"
        case .appearance: return "paintpalette"
        case .shortcuts: return "keyboard"
        case .performance: return "gauge.with.dots.needle.33percent"
        case .permissions: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var dock: DockManager
    @ObservedObject var widgets: WidgetManager
    @ObservedObject var calendar: CalendarService
    @ObservedObject var music: MusicService
    let coordinator: AppCoordinator
    @State private var selection: SettingsSection? = .general
    @State private var loginError: String?
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 28)).foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BetterApple").font(.headline)
                        Text("Make room for better.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(18)
                List(SettingsSection.allCases, selection: $selection) { item in Label(item.rawValue, systemImage: item.symbol).tag(item).padding(.vertical, 3) }.listStyle(.sidebar)
                Text("LOCAL BY DESIGN").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(.tertiary).padding(20)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text((selection ?? .general).rawValue).font(.system(size: 27, weight: .bold)).padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 8)
                content
                if let error = model.persistenceError {
                    Text(error).font(.caption).foregroundStyle(.red).padding()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.tint(.mint)
    }
    @ViewBuilder private var content: some View {
        switch selection ?? .general {
        case .general:
            Form {
                Section {
                    Text("A quieter way to work.").font(.title2.weight(.semibold))
                    Text("Your music, tools and desktop, within reach. Each surface runs independently and stays on your Mac.").foregroundStyle(.secondary)
                }
                Section("Your workspace") {
                    Toggle("Dynamic Island", isOn: $model.settings.island.enabled)
                    Toggle("Independent Dock", isOn: $dock.preferences.enabled)
                    Toggle("Edit widget layout", isOn: $widgets.editing)
                    Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            model.settings.launchAtLogin = enabled; loginError = nil
                        } catch { loginError = error.localizedDescription }
                    }))
                    if let error = loginError { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                Section("Configuration") {
                    HStack {
                        Button("Export JSON…") { coordinator.exportConfiguration() }
                        Button("Import JSON…") { coordinator.importConfiguration() }
                    }
                    Text("Includes Island, Dock, widget layouts and notes. Keep exported files private if your notes contain personal information.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        case .island:
            Form {
                Section("Behavior") {
                    Toggle("Enable Dynamic Island", isOn: $model.settings.island.enabled)
                    Toggle("Expand on hover", isOn: $model.settings.island.hoverToExpand)
                    Toggle("Minimal appearance", isOn: $model.settings.island.minimal)
                    Toggle("Show on every display", isOn: $model.settings.island.allDisplays)
                    Toggle("Allow over full-screen apps", isOn: $model.settings.island.showInFullScreen)
                    slider("Close delay (0 keeps open)", value: $model.settings.island.autoCloseDelay, range: 0...10, unit: "s")
                }
                Section("Geometry") {
                    slider("Compact width", value: $model.settings.island.width, range: 140...500)
                    slider("Compact height", value: $model.settings.island.height, range: 24...64)
                    slider("Expanded width", value: $model.settings.island.expandedWidth, range: 340...650)
                    slider("Expanded height", value: $model.settings.island.expandedHeight, range: 240...500)
                    slider("Horizontal offset", value: $model.settings.island.offsetX, range: -500...500)
                    slider("Distance below menu bar", value: $model.settings.island.offsetY, range: 0...200)
                }
                Section("Modules · use arrows to reorder") {
                    ForEach(ModuleID.allCases) { module in
                        Toggle(module.title, isOn: Binding(get: { model.settings.island.modules.contains(module) }, set: { enabled in
                            if enabled { model.settings.island.modules.append(module) }
                            else if model.settings.island.modules.count > 1 { model.settings.island.modules.removeAll { $0 == module } }
                            if !model.settings.island.modules.contains(model.settings.island.defaultModule) { model.settings.island.defaultModule = model.settings.island.modules[0] }
                        }))
                    }
                    ForEach(Array(model.settings.island.modules.enumerated()), id: \.element) { index, module in
                        HStack {
                            Label(module.title, systemImage: module.symbol); Spacer()
                            Button { model.settings.island.modules.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move up")
                            Button { model.settings.island.modules.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }.disabled(index == model.settings.island.modules.count - 1).help("Move down")
                        }
                    }
                    Picker("Default module", selection: $model.settings.island.defaultModule) { ForEach(model.settings.island.modules) { Text($0.title).tag($0) } }
                }
            }.formStyle(.grouped)
        case .dock: DockSettingsView(manager: dock)
        case .widgets: WidgetSettingsView(manager: widgets)
        case .appearance:
            Form {
                Section("Workspace presets") {
                    ForEach(AppearancePreset.allCases) { preset in
                        HStack {
                            Text(preset.title); Spacer()
                            if model.settings.appearance == preset { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                            Button("Apply") { coordinator.applyPreset(preset) }
                        }
                    }
                }
                Text("Widgets follow their individual theme. The Island uses a dark surface for contrast near the camera; settings follow macOS appearance.").font(.callout).foregroundStyle(.secondary)
            }.formStyle(.grouped)
        case .shortcuts:
            ShortcutSettingsView(service: coordinator.shortcuts)
        case .performance:
            Form {
                Section("Demand-driven services") {
                    Label("System sampling only while visible", systemImage: "cpu")
                    Label("Player polling only while visible and connected", systemImage: "music.note")
                    Label("Calendar refreshes on changes and event boundaries", systemImage: "calendar")
                    Label("Timers use deadlines and survive display sleep", systemImage: "timer")
                }
                Section("Engineering targets") {
                    Text("Target: under 100 MB RAM and near-zero idle CPU. See PERFORMANCE.md for measured results and outstanding profiling. Targets are not guarantees.").foregroundStyle(.secondary)
                    Text("Reduce Motion follows System Settings → Accessibility → Display.").font(.callout)
                }
            }.formStyle(.grouped)
        case .permissions:
            Form {
                Section("Calendar") {
                    Text("Read upcoming events using EventKit. Access is requested only when you choose to connect.").foregroundStyle(.secondary)
                    Button("Allow Calendar Access") { Task { await calendar.requestAccess() } }
                }
                Section("Music automation") {
                    Text("macOS asks for Automation permission separately for each player. Open the player first, then connect.").foregroundStyle(.secondary)
                    HStack {
                        Button("Connect Apple Music") { music.connect(to: .appleMusic) }
                        Button("Connect Spotify") { music.connect(to: .spotify) }
                        Button("Disconnect") { music.disconnect() }
                    }
                    if let error = music.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                Section {
                    Text("Accessibility, administrator access and screen recording are not needed for the current features. BetterApple has no analytics or cloud account.").foregroundStyle(.secondary)
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!) }
                }
            }.formStyle(.grouped)
        case .about:
            Form {
                Section {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 46)).foregroundStyle(.mint)
                    Text("BetterApple").font(.largeTitle.bold())
                    Text("0.1.0 · Native macOS workspace tools").foregroundStyle(.secondary)
                    Text("Built with SwiftUI, AppKit and public system APIs. No external runtime dependencies.")
                }
                Section("Development status") {
                    Text("An early functional development build. Distribution license and public branding remain undecided. Player authorization, multi-display behavior and long-running performance need validation on supported macOS versions.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }
    }
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "pt") -> some View {
        VStack(alignment: .leading) {
            HStack { Text(label); Spacer(); Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(label)
        }
    }
}
