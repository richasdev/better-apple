import AppKit
import SwiftUI
import BetterAppleCore

struct DesktopWidgetView: View {
    @ObservedObject var manager: WidgetManager
    let id: UUID
    private var configuration: WidgetConfiguration? { manager.widgets.first { $0.id == id } }
    var body: some View {
        if let item = configuration {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(item.kind.title, systemImage: item.kind.symbol).font(.system(.caption, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if manager.editing {
                        WidgetDragHandle().frame(width: 18, height: 18).help("Drag to move widget")
                        Button { manager.update(id) { $0.visible = false } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Hide widget")
                    }
                }
                content(item)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial.opacity(item.opacity), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(manager.editing ? Color.accentColor.opacity(0.7) : Color.primary.opacity(item.border ? 0.12 : 0), lineWidth: manager.editing ? 2 : 1))
            .padding(2)
            .preferredColorScheme(item.theme == .automatic ? nil : item.theme == .dark ? .dark : .light)
            .tint(item.accent?.color ?? Color.accentColor)
        }
    }
    @ViewBuilder private func content(_ item: WidgetConfiguration) -> some View {
        switch item.kind {
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 5) {
                    Text(context.date, style: .time).font(.system(size: 42, weight: .light, design: .rounded)).minimumScaleFactor(0.5)
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day()).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        case .analogClock:
            AnalogClockWidget()
        case .calendar:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.date, format: .dateTime.weekday(.wide)).textCase(.uppercase).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text(context.date, format: .dateTime.day()).font(.system(size: 64, weight: .light, design: .rounded))
                    Text(context.date, format: .dateTime.month(.wide).year()).foregroundStyle(.secondary)
                }
            }
        case .events:
            EventsWidget(service: manager.calendar)
        case .calculator:
            CalculatorWidget()
        case .notes:
            TextEditor(text: Binding(get: { configuration?.note ?? "" }, set: { value in manager.update(id) { $0.note = String(value.prefix(100_000)) } }))
                .font(.body).scrollContentBackground(.hidden)
                .accessibilityLabel("Quick note")
        case .music:
            MusicWidget(service: manager.music)
        case .battery:
            BatteryWidget(service: manager.system)
        case .system:
            SystemWidget(service: manager.system)
        case .timer:
            TimerWidget(service: manager.timer)
        }
    }
}

private struct WidgetDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragImageView {
        let view = DragImageView()
        view.image = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Drag to move widget")
        view.contentTintColor = .secondaryLabelColor
        view.imageScaling = .scaleProportionallyDown
        return view
    }
    func updateNSView(_ nsView: DragImageView, context: Context) {}
    final class DragImageView: NSImageView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

private struct AnalogClockWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: context.date)
                let minute = Double(parts.minute ?? 0), second = Double(parts.second ?? 0)
                ZStack {
                    Circle().fill(.primary.opacity(0.04))
                    ForEach(0..<12) { hour in
                        Capsule().fill(.secondary).frame(width: 2, height: size * 0.045).offset(y: -size * 0.43).rotationEffect(.degrees(Double(hour) * 30))
                    }
                    hand(length: size * 0.26, width: 5, angle: Double((parts.hour ?? 0) % 12) * 30 + minute / 2)
                    hand(length: size * 0.36, width: 3, angle: minute * 6 + second / 10)
                    hand(length: size * 0.39, width: 1, angle: second * 6).foregroundStyle(.tint)
                    Circle().fill(.primary).frame(width: 8, height: 8)
                }.frame(width: size, height: size).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore).accessibilityLabel(Text(context.date, style: .time))
            }
        }
    }
    private func hand(length: Double, width: Double, angle: Double) -> some View {
        Capsule().frame(width: width, height: length).offset(y: -length / 2).rotationEffect(.degrees(angle))
    }
}

private struct CalculatorWidget: View {
    @State private var expression = ""
    private var result: String {
        guard !expression.isEmpty else { return "0" }
        do { return try Calculator.evaluate(expression).formatted(.number.precision(.significantDigits(1...12))) }
        catch { return "—" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("(24 + 18) / 3", text: $expression).textFieldStyle(.roundedBorder).accessibilityLabel("Mathematical expression")
            Text(result).font(.system(size: 34, weight: .light, design: .rounded)).textSelection(.enabled).minimumScaleFactor(0.5)
            Button("Copy result", systemImage: "document.on.document") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) }.disabled(result == "—")
        }
    }
}

private struct EventsWidget: View {
    @ObservedObject var service: CalendarService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if service.authorizationStatus != .fullAccess {
                Text("Allow Calendar access to see your upcoming events.").font(.callout).foregroundStyle(.secondary)
                Button("Allow Calendar access") { Task { await service.requestAccess() } }
            } else if service.events.isEmpty {
                Text("No upcoming events").foregroundStyle(.secondary)
            } else {
                ForEach(service.events.prefix(4)) { event in
                    HStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(.tint).frame(width: 3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.callout.weight(.medium)).lineLimit(1)
                            Text(event.startDate, format: .dateTime.weekday().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Open Calendar") { service.openCalendar() }
        }
    }
}

private struct MusicWidget: View {
    @ObservedObject var service: MusicService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let track = service.track {
                HStack(spacing: 12) {
                    Group {
                        if let artwork = service.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").resizable().scaledToFit().padding(18).background(.primary.opacity(0.06)) }
                    }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) { Text(track.title).font(.headline).lineLimit(2); Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                HStack(spacing: 28) {
                    Button { service.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { service.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill") }.accessibilityLabel(track.isPlaying ? "Pause" : "Play")
                    Button { service.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                }.buttonStyle(.plain).font(.title3).frame(maxWidth: .infinity)
            } else {
                Text(service.errorMessage ?? "Connect a running player to control your music.").font(.callout).foregroundStyle(.secondary)
                HStack { ForEach(MusicService.Player.allCases) { player in Button(player.title) { service.connect(to: player) } } }
            }
        }
    }
}

private struct BatteryWidget: View {
    @ObservedObject var service: SystemStatusService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let battery = service.batteryLevel {
                Text(battery, format: .percent.precision(.fractionLength(0))).font(.system(size: 48, weight: .light, design: .rounded))
                ProgressView(value: battery).tint(.green)
            } else { Text("No battery detected").foregroundStyle(.secondary) }
        }
    }
}

private struct SystemWidget: View {
    @ObservedObject var service: SystemStatusService
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent("CPU", value: service.cpuUsage.formatted(.percent.precision(.fractionLength(0))))
            ProgressView(value: service.cpuUsage)
            LabeledContent("Memory", value: ByteCountFormatter.string(fromByteCount: Int64(service.memoryUsedBytes), countStyle: .memory))
            ProgressView(value: service.memoryTotalBytes > 0 ? Double(service.memoryUsedBytes) / Double(service.memoryTotalBytes) : 0)
        }.font(.callout)
    }
}

private struct TimerWidget: View {
    @ObservedObject var service: TimerService
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: "%02d:%02d", Int(ceil(service.remaining)) / 60, Int(ceil(service.remaining)) % 60)).font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
            if service.isRunning || service.isPaused {
                HStack { Button(service.isPaused ? "Resume" : "Pause") { if service.isPaused { service.resume() } else { service.pause() } }; Button("Cancel") { service.cancel() } }
            } else {
                HStack { ForEach([1, 5, 15], id: \.self) { minutes in Button("\(minutes)m") { service.start(seconds: Double(minutes * 60)) } } }
            }
        }
    }
}
