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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    BrandMark().frame(width: 36, height: 36)
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
                    .id(selection ?? .general)
                    .transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                    .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: selection)
                if let error = model.persistenceError {
                    HStack(alignment: .top, spacing: 10) {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button { model.persistenceError = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(SurfaceButtonStyle()).accessibilityLabel("Dismiss error")
                    }
                    .foregroundStyle(.red).padding(12)
                    .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)).padding(16)
                    .transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.tint(model.settings.island.visual.accent.color)
            .accentColor(model.settings.island.visual.accent.color)
            .onReceive(coordinator.$lastSettingsSection.removeDuplicates()) { name in
                guard let section = SettingsSection(rawValue: name), selection != section else { return }
                selection = section
            }
            .onChange(of: selection) { _, selected in coordinator.lastSettingsSection = (selected ?? .general).rawValue }
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: model.persistenceError)
    }
    @ViewBuilder private var content: some View {
        switch selection ?? .general {
        case .general:
            Form {
                Section {
                    Text("A quieter way to work.").font(.title2.weight(.semibold))
                    Text("Your music, tools and desktop, within reach. Each surface runs independently and stays on your Mac.").foregroundStyle(.secondary)
                }
                Section("Choose your features") {
                    feature("Dynamic Island", symbol: "capsule", description: "Music and quick tools, tucked into your camera area.", enabled: $model.settings.island.enabled, destination: .island)
                    feature("Personalized Dock", symbol: "dock.rectangle", description: "Your apps in an independent, customizable Dock.", enabled: $dock.preferences.enabled, destination: .dock)
                    feature("Widgets", symbol: "square.grid.2x2", description: "Clocks, notes and useful information on your desktop.", enabled: $widgets.enabled, destination: .widgets)
                    Text("Use any combination. Turning a feature off keeps its setup and closes its windows. Widgets return with the same content, positions and individual visibility.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Startup") {
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
        case .island: IslandSettingsView(model: model)
        case .dock: DockSettingsView(manager: dock)
        case .widgets: WidgetSettingsView(manager: widgets)
        case .appearance: WorkspaceAppearanceView(model: model, coordinator: coordinator)
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
                Section("Display-adaptive motion") {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        LabeledContent(screen.localizedName, value: "Up to \(screen.maximumFramesPerSecond) Hz")
                    }
                    Text("SwiftUI and AppKit adapt animations to each display. A 120 Hz panel can present up to 120 frames per second; this is a display limit, not a measured FPS result. Reduce Motion remains respected.")
                        .font(.caption).foregroundStyle(.secondary)
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
                Section("Bluetooth notices") {
                    Toggle("Show device connection notices", isOn: $model.settings.island.connectionNotificationsEnabled)
                    Text("Passive connection and disconnection events for Dynamic Island. No scanning, pairing or AirPods battery access. macOS controls Bluetooth permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Music automation") {
                    Text("Choose a player to connect. Desktop players open when needed; macOS asks for Automation access separately for each app.").foregroundStyle(.secondary)
                    HStack {
                        Menu("Connect player") {
                            ForEach(music.availablePlayers) { player in
                                Button(player.title) { music.connect(to: player) }
                            }
                        }
                        Button("Disconnect") { music.disconnect() }
                    }
                    Text("Selected: \(music.selectedPlayer.title)").font(.caption)
                    if let help = music.connectionHelp { Text(help).font(.caption).foregroundStyle(.secondary) }
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
                    BrandMark().frame(width: 76, height: 76)
                    Text("BetterApple").font(.largeTitle.bold())
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Native macOS workspace tools").foregroundStyle(.secondary)
                    Text("Built with SwiftUI, AppKit and public system APIs. No external runtime dependencies.")
                }
                Section("Development status") {
                    Text("An early functional development build. Distribution license and public branding remain undecided. Player authorization, multi-display behavior and long-running performance need validation on supported macOS versions.").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }
    }
    private func feature(_ title: String, symbol: String, description: String, enabled: Binding<Bool>, destination: SettingsSection) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 21, weight: .medium))
                .foregroundStyle(enabled.wrappedValue ? model.settings.island.visual.accent.color : Color.secondary)
                .frame(width: 32).accessibilityHidden(true)
            Toggle(isOn: enabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).tint(model.settings.island.visual.accent.color)
                .accessibilityHint("Turning off preserves your configuration")
            Button { selection = destination } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless).help("Configure \(title)").accessibilityLabel("Configure \(title)")
        }.padding(.vertical, 8)
    }
    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String = "pt") -> some View {
        VStack(alignment: .leading) {
            HStack { Text(label); Spacer(); Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).accessibilityLabel(label)
        }
    }
}
