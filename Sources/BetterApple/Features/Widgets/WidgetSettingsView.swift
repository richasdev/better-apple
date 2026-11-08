import AppKit
import SwiftUI

struct WidgetSettingsView: View {
    @ObservedObject var manager: WidgetManager
    @State private var expanded = Set<UUID>()
    @State private var pendingNoteRemoval: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let commonZones = ["UTC", "Asia/Tokyo", "Asia/Seoul", "Asia/Shanghai", "Asia/Singapore", "Europe/London", "Europe/Paris", "America/New_York", "America/Los_Angeles", "America/Sao_Paulo", "Australia/Sydney"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Widgets", isOn: $manager.enabled).toggleStyle(.switch)
                if !manager.enabled {
                    Text("Widgets are off. Your content and layout are saved; turn them on to restore your desktop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Your desktop") {
                HStack {
                    Label("\(manager.widgets.filter(\.visible).count) selected · \(manager.widgets.count) total", systemImage: "square.grid.2x2")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu("Add widget") {
                        ForEach(DesktopWidgetKind.allCases) { kind in Button(kind.title, systemImage: kind.symbol) { manager.add(kind: kind) } }
                    }.disabled(manager.widgets.count >= 30)
                }
                Toggle("Edit layout", isOn: $manager.editing).disabled(!manager.enabled)
                Toggle("Snap to grid after moving or resizing", isOn: $manager.layoutPreferences.snapToGrid)
                if manager.layoutPreferences.snapToGrid {
                    Picker("Grid spacing", selection: $manager.layoutPreferences.gridSize) {
                        ForEach([12.0, 16, 20, 24, 32, 48, 64], id: \.self) { Text("\(Int($0)) pt").tag($0) }
                        if ![12.0, 16, 20, 24, 32, 48, 64].contains(manager.layoutPreferences.gridSize) {
                            Text("\(Int(manager.layoutPreferences.gridSize)) pt").tag(manager.layoutPreferences.gridSize)
                        }
                    }.transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                }
                HStack {
                    Button("Arrange visible widgets") { manager.arrangeVisible() }.disabled(!manager.enabled || !manager.widgets.contains(where: \.visible))
                    Button("Show all") { manager.setAllVisible(true) }.disabled(manager.widgets.isEmpty)
                    Button("Hide all") { manager.setAllVisible(false) }.disabled(manager.widgets.isEmpty)
                }
                Text("Use the drag handle in edit mode to move a widget; resize from its edges. Right-click any widget for quick actions. Layout and notes save automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = manager.layoutMessage {
                    Label(message, systemImage: "rectangle.3.group").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Layout status: \(message)")
                }
            }
            if manager.widgets.isEmpty {
                Section {
                    ContentUnavailableView("Make space for what matters", systemImage: "square.grid.2x2", description: Text("Add a clock, quick note, timer or live system widget to begin."))
                }
            }
            Section("Widgets") {
                ForEach(manager.widgets) { item in
                    DisclosureGroup(isExpanded: expansion(item.id)) {
                        controls(item)
                    } label: {
                        HStack {
                            Label(item.displayTitle, systemImage: item.kind.symbol).lineLimit(1)
                            Spacer()
                            Text(item.visible ? (manager.enabled ? "Visible" : "Feature off") : "Hidden").font(.caption).foregroundStyle(item.visible ? .secondary : .tertiary)
                        }
                    }
                }
            }
        }.formStyle(.grouped)
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: manager.layoutPreferences.snapToGrid)
            .onChange(of: manager.widgets.count) { oldCount, newCount in
                withAnimation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content)) {
                    if newCount > oldCount, let last = manager.widgets.last { expanded.insert(last.id) }
                    expanded.formIntersection(manager.widgets.map(\.id))
                }
            }
            .confirmationDialog("Remove this note widget?", isPresented: Binding(get: { pendingNoteRemoval != nil }, set: { if !$0 { pendingNoteRemoval = nil } }), titleVisibility: .visible) {
                Button("Remove note", role: .destructive) {
                    if let id = pendingNoteRemoval { manager.remove(id: id) }
                    pendingNoteRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingNoteRemoval = nil }
            } message: { Text("The note’s contents will be deleted from this layout.") }
    }

    @ViewBuilder private func controls(_ item: WidgetConfiguration) -> some View {
        Toggle("Visible", isOn: binding(item, \.visible))
        TextField("Custom title", text: Binding(get: { current(item).title ?? "" }, set: { text in manager.update(item.id) { $0.title = String(text.prefix(80)) } }))
        Picker("Theme", selection: binding(item, \.theme)) {
            ForEach(DesktopWidgetTheme.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
        Picker("Accent color", selection: binding(item, \.accent)) {
            Text("System accent").tag(Optional<DesktopWidgetAccent>.none)
            ForEach(DesktopWidgetAccent.allCases) { accent in Text(accent.rawValue.capitalized).tag(Optional(accent)) }
        }
        if item.kind != .analogClock && item.kind != .calculator {
            LabeledContent("Text size", value: "\(Int(current(item).textSize)) pt")
            Slider(value: Binding(get: { current(item).textSize }, set: { size in manager.update(item.id) { $0.fontSize = size.rounded() } }), in: 10...64, step: 1)
                .accessibilityLabel("Widget text size")
        }
        LabeledContent("Opacity") { Slider(value: binding(item, \.opacity), in: 0.2...1).frame(maxWidth: 220).accessibilityLabel("Widget opacity") }
        Toggle("Border", isOn: binding(item, \.border))
        Toggle("Shadow", isOn: binding(item, \.shadow))
        Divider()
        typeControls(item)
        HStack {
            Button("Center") { manager.center(id: item.id) }
            Button("Bring forward") { manager.bringForward(id: item.id) }.disabled(!item.visible)
            Button("Duplicate") { if let id = manager.duplicate(id: item.id) { expanded.insert(id) } }.disabled(manager.widgets.count >= 30)
            Spacer()
            Button("Remove", role: .destructive) {
                if item.kind == .notes && !current(item).note.isEmpty { pendingNoteRemoval = item.id }
                else { manager.remove(id: item.id) }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func typeControls(_ item: WidgetConfiguration) -> some View {
        switch item.kind {
        case .clock, .analogClock:
            Toggle("Show seconds", isOn: option(item, \.showSeconds))
            if item.kind == .clock { Toggle("24-hour clock", isOn: option(item, \.use24Hour)) }
            Toggle("Show date", isOn: option(item, \.showDate))
            Picker("Time zone", selection: Binding(get: { current(item).displayOptions.clockTimeZoneIdentifier ?? "" }, set: { zone in
                manager.update(item.id) { value in var options = value.displayOptions; options.clockTimeZoneIdentifier = zone.isEmpty ? nil : zone; value.options = options }
            })) {
                Text("Follow this Mac").tag("")
                ForEach(commonZones, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                if let customZone = current(item).displayOptions.clockTimeZoneIdentifier, !commonZones.contains(customZone) { Text(customZone).tag(customZone) }
            }
            Text("Without seconds, clocks refresh once per minute.").font(.caption).foregroundStyle(.secondary)
        case .calendar:
            Text("Shows the current date using this Mac’s calendar and locale.").font(.caption).foregroundStyle(.secondary)
        case .events:
            Stepper("Show up to \(current(item).displayOptions.eventLimit) events", value: option(item, \.eventLimit), in: 1...8)
        case .music:
            Toggle("Album artwork", isOn: option(item, \.showArtwork))
            Toggle("Artist name", isOn: option(item, \.showArtist))
            Toggle("Playback progress", isOn: option(item, \.showProgress))
        case .battery:
            Toggle("Charge bar", isOn: option(item, \.showProgress))
            Toggle("Charging status", isOn: option(item, \.showChargingState))
        case .system:
            Toggle("CPU usage", isOn: option(item, \.showCPU)).disabled(!current(item).displayOptions.showMemory)
            Toggle("Memory usage", isOn: option(item, \.showMemory)).disabled(!current(item).displayOptions.showCPU)
            Toggle("Usage bars", isOn: option(item, \.showProgress))
        case .timer:
            Toggle("Countdown progress", isOn: option(item, \.showProgress))
            Text("Timer and calculator state are shared with the Island.").font(.caption).foregroundStyle(.secondary)
        case .calculator:
            Text("Uses the same calculator and optional history as the Island.").font(.caption).foregroundStyle(.secondary)
        case .notes:
            Text("Notes stay on this Mac and are included in configuration exports.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func current(_ item: WidgetConfiguration) -> WidgetConfiguration { manager.widgets.first { $0.id == item.id } ?? item }
    private func binding<T>(_ item: WidgetConfiguration, _ keyPath: WritableKeyPath<WidgetConfiguration, T>) -> Binding<T> {
        Binding(get: { current(item)[keyPath: keyPath] }, set: { value in manager.update(item.id) { $0[keyPath: keyPath] = value } })
    }
    private func option<T>(_ item: WidgetConfiguration, _ keyPath: WritableKeyPath<WidgetDisplayOptions, T>) -> Binding<T> {
        Binding(get: { current(item).displayOptions[keyPath: keyPath] }, set: { value in
            manager.update(item.id) { item in var options = item.displayOptions; options[keyPath: keyPath] = value; item.options = options }
        })
    }
    private func expansion(_ id: UUID) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) }, set: { value in
            withAnimation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content)) {
                if value { expanded.insert(id) } else { expanded.remove(id) }
            }
        })
    }
}
