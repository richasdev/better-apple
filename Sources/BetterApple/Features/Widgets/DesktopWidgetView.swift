import AppKit
import SwiftUI
import BetterAppleCore

struct DesktopWidgetView: View {
    @ObservedObject var manager: WidgetManager
    let id: UUID
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastKnownConfiguration: WidgetConfiguration?
    @State private var confirmingRemoval = false
    init(manager: WidgetManager, id: UUID) {
        self.manager = manager; self.id = id
        _lastKnownConfiguration = State(initialValue: manager.widgets.first { $0.id == id })
    }
    // Retain the last presentation only for the finite removal fade, avoiding an empty flash.
    private var configuration: WidgetConfiguration? { manager.widgets.first { $0.id == id } ?? lastKnownConfiguration }
    var body: some View {
        if let item = configuration {
            let compact = item.height < 140 && [.clock, .calendar, .battery, .system].contains(item.kind)
            VStack(alignment: .leading, spacing: compact ? 0 : 14) {
                if (item.displaysHeader && !compact) || manager.editing {
                HStack {
                    Label(item.displayTitle, systemImage: item.kind.symbol).font(.system(.caption, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if manager.editing {
                        WidgetDragHandle(onFinish: { manager.finishEditingFrame(id: id) }).frame(width: 24, height: 24).help("Drag to move widget")
                            .transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                        Button { manager.update(id) { $0.visible = false } } label: { Image(systemName: "xmark") }
                            .buttonStyle(SurfaceButtonStyle()).accessibilityLabel("Hide widget")
                            .transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                    }
                }.frame(height: 28)
                    .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: manager.editing)
                }
                if [.clock, .calendar, .analogClock, .notes, .calculator].contains(item.kind) || ([.battery, .system].contains(item.kind) && !manager.editing && !item.displaysHeader) {
                    content(item)
                } else {
                    ScrollView {
                        content(item).frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.automatic)
                }
                Spacer(minLength: 0)
            }
            .padding(compact || (item.surface == .minimal && !manager.editing) ? 8 : 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if item.surface != .minimal {
                    if item.surface == .card {
                        let dark = item.theme == .dark || (item.theme == .automatic && colorScheme == .dark)
                        RoundedRectangle(cornerRadius: item.radius).fill((dark ? Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1) : Color(nsColor: .windowBackgroundColor)).opacity(reduceTransparency ? 1 : item.opacity))
                    } else if reduceTransparency {
                        RoundedRectangle(cornerRadius: item.radius).fill(Color(nsColor: .windowBackgroundColor))
                    } else if item.surface == .glass {
                        RoundedRectangle(cornerRadius: item.radius).fill(.ultraThinMaterial.opacity(item.opacity))
                    } else {
                        RoundedRectangle(cornerRadius: item.radius).fill(.regularMaterial.opacity(item.opacity))
                    }
                }
            }
            .foregroundStyle(item.textColor)
            .opacity(item.surface == .minimal && !manager.editing ? item.opacity : 1)
            .overlay(RoundedRectangle(cornerRadius: item.radius).stroke(manager.editing ? Color.accentColor.opacity(0.7) : item.textColor.opacity(item.border && item.surface != .minimal ? 0.12 : 0), lineWidth: manager.editing ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: item.surface == .minimal ? 0 : item.radius))
            .padding(2)
            .preferredColorScheme(item.theme == .automatic ? nil : item.theme == .dark ? .dark : .light)
            .environment(\.colorScheme, item.theme == .automatic ? colorScheme : item.theme == .dark ? .dark : .light)
            .tint(item.accent?.color ?? Color.accentColor)
            .accentColor(item.accent?.color ?? Color.accentColor)
            .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: manager.editing)
            .onReceive(manager.$widgets) { widgets in
                if let current = widgets.first(where: { $0.id == id }) { lastKnownConfiguration = current }
            }
            .contextMenu {
                Button(manager.editing ? "Finish editing" : "Edit layout", systemImage: "slider.horizontal.3") { manager.editing.toggle() }
                Button("Bring forward", systemImage: "square.3.layers.3d.top.filled") { manager.bringForward(id: id) }
                Button("Center on display", systemImage: "scope") { manager.center(id: id) }
                Button("Duplicate widget", systemImage: "plus.square.on.square") { manager.duplicate(id: id) }.disabled(manager.widgets.count >= 30)
                Divider()
                Button("Hide widget", systemImage: "eye.slash") { manager.update(id) { $0.visible = false } }
                Button("Remove widget", systemImage: "trash", role: .destructive) {
                    if item.kind == .notes && !item.note.isEmpty { confirmingRemoval = true }
                    else { manager.remove(id: id) }
                }
            }
            .confirmationDialog("Remove this note widget?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove note", role: .destructive) { manager.remove(id: id) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The note’s contents will be deleted from this layout.") }
        }
    }
    @ViewBuilder private func content(_ item: WidgetConfiguration) -> some View {
        switch item.kind {
        case .clock:
            let condensed = item.height < 140
            TimelineView(.periodic(from: WidgetClockFormatting.scheduleStart(showSeconds: item.displayOptions.showSeconds), by: item.displayOptions.showSeconds ? 1 : 60)) { context in
                VStack(alignment: .leading, spacing: 5) {
                    Text(WidgetClockFormatting.time(context.date, options: item.displayOptions)).font(.system(size: condensed ? min(item.textSize, max(12, (item.height - 40) * 0.75)) : item.textSize, weight: item.weight, design: item.surface == .minimal ? .default : .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.2)
                    if item.displayOptions.showDate && !condensed {
                        Text(WidgetClockFormatting.date(context.date, zone: item.displayOptions.timeZone)).font(.system(size: min(24, max(13, item.textSize / 7)), weight: .medium)).foregroundStyle(item.textColor.opacity(0.8))
                    }
                    if !condensed && (item.displayOptions.showTimeZone || item.displayOptions.clockTimeZoneIdentifier != nil) {
                        Text(item.displayOptions.timeZone.abbreviation(for: context.date) ?? item.displayOptions.timeZone.identifier)
                            .font(.caption.weight(.medium)).foregroundStyle(item.textColor.opacity(0.65))
                            .accessibilityLabel("Time zone: \(item.displayOptions.timeZone.identifier)")
                    }
                }
            }
        case .analogClock:
            AnalogClockWidget(options: item.displayOptions)
        case .calendar:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if item.height < 140 {
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: min(item.textSize, 28), weight: item.weight))
                        .lineLimit(1).minimumScaleFactor(0.3)
                } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.date, format: .dateTime.weekday(.wide)).textCase(.uppercase).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text(context.date, format: .dateTime.day()).font(.system(size: item.textSize, weight: item.weight, design: .rounded)).lineLimit(1).minimumScaleFactor(0.4)
                    Text(context.date, format: .dateTime.month(.wide).year()).foregroundStyle(.secondary)
                }
                }
            }
        case .events:
            EventsWidget(service: manager.calendar, options: item.displayOptions, fontSize: item.textSize)
        case .calculator:
            CalculatorModuleView(calculator: manager.calculator, compact: true)
        case .notes:
            TextEditor(text: Binding(get: { configuration?.note ?? "" }, set: { value in manager.update(id) { $0.note = String(value.prefix(100_000)) } }))
                .font(.system(size: item.textSize)).scrollContentBackground(.hidden)
                .accessibilityLabel("Quick note")
        case .music:
            MusicWidget(service: manager.music, options: item.displayOptions, fontSize: item.textSize)
        case .battery:
            BatteryWidget(service: manager.system, options: item.displayOptions, fontSize: item.textSize, weight: item.weight, compact: item.height < 130)
        case .system:
            SystemWidget(service: manager.system, options: item.displayOptions, fontSize: item.textSize, weight: item.weight, compact: item.height < 160)
        case .timer:
            TimerWidget(service: manager.timer, options: item.displayOptions, fontSize: item.textSize)
        }
    }
}

private struct WidgetDragHandle: NSViewRepresentable {
    let onFinish: () -> Void
    func makeNSView(context: Context) -> DragImageView {
        let view = DragImageView()
        view.image = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Drag to move widget")
        view.contentTintColor = .secondaryLabelColor
        view.imageScaling = .scaleProportionallyDown
        view.onFinish = onFinish
        return view
    }
    func updateNSView(_ nsView: DragImageView, context: Context) { nsView.onFinish = onFinish }
    final class DragImageView: NSImageView {
        var onFinish: (() -> Void)?
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event); onFinish?() }
    }
}

private struct AnalogClockWidget: View {
    let options: WidgetDisplayOptions
    var body: some View {
        TimelineView(.periodic(from: WidgetClockFormatting.scheduleStart(showSeconds: options.showSeconds), by: options.showSeconds ? 1 : 60)) { context in
            VStack(spacing: 8) {
              GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let parts = WidgetClockFormatting.components(context.date, zone: options.timeZone)
                let minute = Double(parts.minute ?? 0), second = Double(parts.second ?? 0)
                ZStack {
                    Circle().fill(.primary.opacity(0.04))
                    ForEach(0..<12) { hour in
                        Capsule().fill(.secondary).frame(width: 2, height: size * 0.045).offset(y: -size * 0.43).rotationEffect(.degrees(Double(hour) * 30))
                    }
                    hand(length: size * 0.26, width: 5, angle: Double((parts.hour ?? 0) % 12) * 30 + minute / 2)
                    hand(length: size * 0.36, width: 3, angle: minute * 6 + second / 10)
                    if options.showSeconds { hand(length: size * 0.39, width: 1, angle: second * 6).foregroundStyle(.tint) }
                    Circle().fill(.primary).frame(width: 8, height: 8)
                }.frame(width: size, height: size).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore).accessibilityLabel(WidgetClockFormatting.time(context.date, options: options))
              }
              if options.showDate { Text(WidgetClockFormatting.date(context.date, zone: options.timeZone)).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func hand(length: Double, width: Double, angle: Double) -> some View {
        Capsule().frame(width: width, height: length).offset(y: -length / 2).rotationEffect(.degrees(angle))
    }
}

private struct EventsWidget: View {
    @ObservedObject var service: CalendarService
    let options: WidgetDisplayOptions
    let fontSize: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if service.authorizationStatus != .fullAccess {
                Text("Allow Calendar access to see your upcoming events.").font(.callout).foregroundStyle(.secondary)
                Button("Allow Calendar access") { Task { await service.requestAccess() } }
            } else if service.events.isEmpty {
                Text("No upcoming events").foregroundStyle(.secondary)
            } else {
                  VStack(alignment: .leading, spacing: 12) {
                   ForEach(service.events.prefix(options.eventLimit)) { event in
                    HStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(.tint).frame(width: 3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.system(size: fontSize, weight: .medium)).lineLimit(2)
                            Text(event.startDate, format: .dateTime.weekday().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                   }
                  }
            }
            Button("Open Calendar") { service.openCalendar() }
        }
    }
}

private struct MusicWidget: View {
    @ObservedObject var service: MusicService
    let options: WidgetDisplayOptions
    let fontSize: Double
    @State private var localPosition = 0.0
    @State private var isScrubbing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let track = service.track {
                HStack(spacing: 12) {
                    if options.showArtwork {
                      Group {
                        if let artwork = service.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").resizable().scaledToFit().padding(18).background(.primary.opacity(0.06)) }
                      }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.system(size: fontSize, weight: .semibold)).lineLimit(2)
                        if options.showArtist { Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                if options.showProgress, track.duration > 0 {
                    Slider(value: $localPosition, in: 0...track.duration, onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing { service.seek(to: localPosition) }
                    }).accessibilityLabel("Playback position")
                }
                HStack(spacing: 28) {
                    Button { service.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { service.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill") }.accessibilityLabel(track.isPlaying ? "Pause" : "Play")
                    Button { service.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                }.buttonStyle(SurfaceButtonStyle()).font(.title3).frame(maxWidth: .infinity)
            } else {
                Text(service.errorMessage ?? "Connect a running player to control your music.").font(.callout).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { playerButtons }
                    VStack(alignment: .leading) { playerButtons }
                }
            }
        }
        .onAppear { synchronizePosition() }
        .onChange(of: service.track) { _, _ in if !isScrubbing { synchronizePosition() } }
    }
    @ViewBuilder private var playerButtons: some View {
        ForEach(service.availablePlayers) { player in Button(player.title) { service.connect(to: player) } }
    }
    private func synchronizePosition() {
        guard let track = service.track else { localPosition = 0; return }
        localPosition = min(max(0, track.position), max(0, track.duration))
    }
}

private struct BatteryWidget: View {
    @ObservedObject var service: SystemStatusService
    let options: WidgetDisplayOptions
    let fontSize: Double
    let weight: Font.Weight
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            if let battery = service.batteryLevel {
                HStack {
                    Text(battery, format: .percent.precision(.fractionLength(0))).font(.system(size: compact ? min(fontSize, 28) : fontSize, weight: weight, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
                    if compact && options.showChargingState {
                        Spacer()
                        Image(systemName: service.isCharging ? "battery.100.bolt" : "battery.100percent")
                            .accessibilityLabel(service.isCharging ? "Charging" : "Not charging")
                    }
                }
                if options.showProgress { ProgressView(value: battery) }
                if options.showChargingState && !compact {
                    Label(service.isCharging ? "Charging" : battery >= 0.99 ? "Fully charged" : "Not charging", systemImage: service.isCharging ? "battery.100.bolt" : "battery.100percent")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("No battery detected").foregroundStyle(.secondary) }
        }
    }
}

private struct SystemWidget: View {
    @ObservedObject var service: SystemStatusService
    let options: WidgetDisplayOptions
    let fontSize: Double
    let weight: Font.Weight
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 16) {
            if options.showCPU {
                LabeledContent("CPU", value: service.cpuUsage.formatted(.percent.precision(.fractionLength(0))))
                if options.showProgress { ProgressView(value: service.cpuUsage) }
            }
            if options.showMemory {
                LabeledContent("Memory", value: ByteCountFormatter.string(fromByteCount: Int64(service.memoryUsedBytes), countStyle: .memory))
                if !compact { Text("of \(ByteCountFormatter.string(fromByteCount: Int64(service.memoryTotalBytes), countStyle: .memory)) physical memory").font(.caption).foregroundStyle(.secondary) }
                if options.showProgress { ProgressView(value: service.memoryTotalBytes > 0 ? Double(service.memoryUsedBytes) / Double(service.memoryTotalBytes) : 0) }
            }
        }.font(.system(size: fontSize, weight: weight))
    }
}

private struct TimerWidget: View {
    @ObservedObject var service: TimerService
    let options: WidgetDisplayOptions
    let fontSize: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !service.label.isEmpty { Text(service.label).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Text(Duration.seconds(max(0, service.remaining.rounded(.up))).formatted(.time(pattern: service.remaining >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                .font(.system(size: fontSize, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: Int(ceil(service.remaining)))
            if options.showProgress && (service.isRunning || service.isPaused) { ProgressView(value: service.progress).accessibilityLabel("Timer progress") }
            if service.isRunning || service.isPaused {
                HStack { Button(service.isPaused ? "Resume" : "Pause") { if service.isPaused { service.resume() } else { service.pause() } }; Button("Cancel") { service.cancel() } }
            } else if service.didComplete {
                Label("Timer complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                HStack { Button("Restart") { service.restart() }; Button("Dismiss") { service.dismissCompletion() } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(service.presetMinutes.prefix(4), id: \.self) { minutes in Button("\(minutes)m") { service.start(seconds: Double(minutes * 60)) } } }
                }
            }
        }
    }
}

enum WidgetClockFormatting {
    static func scheduleStart(showSeconds: Bool, now: Date = .now) -> Date {
        let step = showSeconds ? 1.0 : 60.0
        return Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / step) * step)
    }
    static func time(_ date: Date, options: WidgetDisplayOptions) -> String {
        var format = Date.FormatStyle()
            .hour(options.use24Hour ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
        if options.showSeconds { format = format.second(.twoDigits) }
        format.timeZone = options.timeZone
        format.locale = Locale(identifier: options.use24Hour ? "en_GB" : "en_US")
        return date.formatted(format)
    }
    static func date(_ date: Date, zone: TimeZone) -> String {
        var format = Date.FormatStyle().weekday(.wide).month(.wide).day()
        format.timeZone = zone
        return date.formatted(format)
    }
    static func components(_ date: Date, zone: TimeZone) -> DateComponents {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = zone
        return calendar.dateComponents([.hour, .minute, .second], from: date)
    }
}
