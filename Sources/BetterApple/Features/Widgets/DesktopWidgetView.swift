import AppKit
import SwiftUI
import BetterAppleCore

struct DesktopWidgetView: View {
    @ObservedObject var manager: WidgetManager
    let id: UUID
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var configuration: WidgetConfiguration? { manager.widgets.first { $0.id == id } }
    var body: some View {
        if let item = configuration {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(item.displayTitle, systemImage: item.kind.symbol).font(.system(.caption, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if manager.editing {
                        WidgetDragHandle(onFinish: { manager.finishEditingFrame(id: id) }).frame(width: 18, height: 18).help("Drag to move widget")
                        Button { manager.update(id) { $0.visible = false } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Hide widget")
                    }
                }
                content(item)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: 22).fill(.ultraThinMaterial.opacity(item.opacity))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(manager.editing ? Color.accentColor.opacity(0.7) : Color.primary.opacity(item.border ? 0.12 : 0), lineWidth: manager.editing ? 2 : 1))
            .padding(2)
            .preferredColorScheme(item.theme == .automatic ? nil : item.theme == .dark ? .dark : .light)
            .tint(item.accent?.color ?? Color.accentColor)
            .contextMenu {
                Button(manager.editing ? "Finish editing" : "Edit layout", systemImage: "slider.horizontal.3") { manager.editing.toggle() }
                Button("Bring forward", systemImage: "square.3.layers.3d.top.filled") { manager.bringForward(id: id) }
                Button("Center on display", systemImage: "scope") { manager.center(id: id) }
                Button("Duplicate widget", systemImage: "plus.square.on.square") { manager.duplicate(id: id) }.disabled(manager.widgets.count >= 30)
                Divider()
                Button("Hide widget", systemImage: "eye.slash") { manager.update(id) { $0.visible = false } }
                Button("Remove widget", systemImage: "trash", role: .destructive) { manager.remove(id: id) }
            }
        }
    }
    @ViewBuilder private func content(_ item: WidgetConfiguration) -> some View {
        switch item.kind {
        case .clock:
            TimelineView(.periodic(from: WidgetClockFormatting.scheduleStart(showSeconds: item.displayOptions.showSeconds), by: item.displayOptions.showSeconds ? 1 : 60)) { context in
                VStack(alignment: .leading, spacing: 5) {
                    Text(WidgetClockFormatting.time(context.date, options: item.displayOptions)).font(.system(size: item.textSize, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                    if item.displayOptions.showDate {
                        Text(WidgetClockFormatting.date(context.date, zone: item.displayOptions.timeZone)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let zone = item.displayOptions.clockTimeZoneIdentifier { Text(zone.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.tertiary) }
                }
            }
        case .analogClock:
            AnalogClockWidget(options: item.displayOptions)
        case .calendar:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.date, format: .dateTime.weekday(.wide)).textCase(.uppercase).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text(context.date, format: .dateTime.day()).font(.system(size: item.textSize, weight: .light, design: .rounded))
                    Text(context.date, format: .dateTime.month(.wide).year()).foregroundStyle(.secondary)
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
            BatteryWidget(service: manager.system, options: item.displayOptions, fontSize: item.textSize)
        case .system:
            SystemWidget(service: manager.system, options: item.displayOptions, fontSize: item.textSize)
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
                ScrollView {
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
            }
            Button("Open Calendar") { service.openCalendar() }
        }
    }
}

private struct MusicWidget: View {
    @ObservedObject var service: MusicService
    let options: WidgetDisplayOptions
    let fontSize: Double
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
                    Slider(value: Binding(get: { min(track.duration, max(0, track.position)) }, set: { service.seek(to: $0) }), in: 0...track.duration).accessibilityLabel("Playback position")
                }
                HStack(spacing: 28) {
                    Button { service.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { service.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill") }.accessibilityLabel(track.isPlaying ? "Pause" : "Play")
                    Button { service.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                }.buttonStyle(.plain).font(.title3).frame(maxWidth: .infinity)
            } else {
                Text(service.errorMessage ?? "Connect a running player to control your music.").font(.callout).foregroundStyle(.secondary)
                HStack { ForEach(service.availablePlayers) { player in Button(player.title) { service.connect(to: player) } } }
            }
        }
    }
}

private struct BatteryWidget: View {
    @ObservedObject var service: SystemStatusService
    let options: WidgetDisplayOptions
    let fontSize: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let battery = service.batteryLevel {
                Text(battery, format: .percent.precision(.fractionLength(0))).font(.system(size: fontSize, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
                if options.showProgress { ProgressView(value: battery) }
                if options.showChargingState {
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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if options.showCPU {
                LabeledContent("CPU", value: service.cpuUsage.formatted(.percent.precision(.fractionLength(0))))
                if options.showProgress { ProgressView(value: service.cpuUsage) }
            }
            if options.showMemory {
                LabeledContent("Memory", value: ByteCountFormatter.string(fromByteCount: Int64(service.memoryUsedBytes), countStyle: .memory))
                Text("of \(ByteCountFormatter.string(fromByteCount: Int64(service.memoryTotalBytes), countStyle: .memory)) physical memory").font(.caption).foregroundStyle(.secondary)
                if options.showProgress { ProgressView(value: service.memoryTotalBytes > 0 ? Double(service.memoryUsedBytes) / Double(service.memoryTotalBytes) : 0) }
            }
        }.font(.system(size: fontSize))
    }
}

private struct TimerWidget: View {
    @ObservedObject var service: TimerService
    let options: WidgetDisplayOptions
    let fontSize: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !service.label.isEmpty { Text(service.label).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Text(String(format: "%02d:%02d", Int(ceil(service.remaining)) / 60, Int(ceil(service.remaining)) % 60)).font(.system(size: fontSize, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            if options.showProgress && (service.isRunning || service.isPaused) { ProgressView(value: service.progress).accessibilityLabel("Timer progress") }
            if service.isRunning || service.isPaused {
                HStack { Button(service.isPaused ? "Resume" : "Pause") { if service.isPaused { service.resume() } else { service.pause() } }; Button("Cancel") { service.cancel() } }
            } else if service.didComplete {
                Label("Timer complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                HStack { Button("Restart") { service.restart() }; Button("Dismiss") { service.dismissCompletion() } }
            } else {
                HStack { ForEach(service.presetMinutes.prefix(4), id: \.self) { minutes in Button("\(minutes)m") { service.start(seconds: Double(minutes * 60)) } } }
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
