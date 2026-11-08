import SwiftUI
import BetterAppleCore

@MainActor
protocol IslandModule {
    var id: ModuleID { get }
    func content() -> AnyView
}

struct NativeIslandModule: IslandModule {
    let id: ModuleID
    let build: @MainActor () -> AnyView
    func content() -> AnyView { build() }
}

@MainActor
final class IslandModuleRegistry {
    private var modules: [ModuleID: any IslandModule] = [:]
    func register(_ module: any IslandModule) { modules[module.id] = module }
    func content(for id: ModuleID) -> AnyView { modules[id]?.content() ?? AnyView(EmptyView()) }
}

struct CalculatorModuleView: View {
    @State private var expression = ""
    @State private var copied = false
    private var result: String {
        guard !expression.isEmpty else { return "0" }
        do { return try Calculator.evaluate(expression).formatted(.number.precision(.significantDigits(12))) }
        catch { return "—" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("(24 + 18) / 6", text: $expression).textFieldStyle(.roundedBorder)
                .font(.system(size: 21, design: .monospaced)).accessibilityLabel("Mathematical expression")
            HStack {
                Text(result).font(.system(size: 34, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string); copied = true } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }.disabled(result == "—").help("Copy result")
            }
            Text("+  −  ×  ÷  ^  ( )").font(.caption).foregroundStyle(.secondary)
        }.onChange(of: expression) { _, _ in copied = false }
    }
}

struct TimerModuleView: View {
    @ObservedObject var timer: TimerService
    @State private var minutes = 5.0
    var body: some View {
        VStack(spacing: 14) {
            Text(Duration.seconds(timer.remaining).formatted(.time(pattern: .minuteSecond)))
                .font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(timer.didComplete ? .green : .primary)
            if !timer.isRunning && !timer.isPaused {
                HStack {
                    ForEach([1, 5, 15, 25], id: \.self) { value in
                        Button("\(value)m") { timer.start(seconds: Double(value * 60)) }
                    }
                }
                HStack {
                    TextField("Minutes", value: $minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                    Button("Start") { timer.start(seconds: min(86400, max(1, minutes * 60))) }.keyboardShortcut(.return, modifiers: [])
                }
            } else {
                HStack {
                    Button(timer.isPaused ? "Resume" : "Pause") { if timer.isPaused { timer.resume() } else { timer.pause() } }
                    Button("Cancel", role: .destructive) { timer.cancel() }
                }
            }
            if timer.didComplete { Text("Timer complete").foregroundStyle(.green) }
        }.frame(maxWidth: .infinity)
    }
}

struct CalendarModuleView: View {
    @ObservedObject var calendar: CalendarService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day()).font(.headline)
                Spacer()
                Button { calendar.openCalendar() } label: { Image(systemName: "arrow.up.right") }.help("Open Calendar")
            }
            if calendar.authorizationStatus != .fullAccess {
                Text("Connect your calendar to see upcoming events.").foregroundStyle(.secondary)
                Button("Allow Calendar Access") { Task { await calendar.requestAccess() } }
            } else if calendar.events.isEmpty {
                Label("No upcoming events", systemImage: "calendar.badge.checkmark").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(calendar.events.prefix(12)) { event in
                            HStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 2).fill(.mint).frame(width: 3)
                                VStack(alignment: .leading) {
                                    Text(event.title).font(.callout.weight(.medium)).lineLimit(2)
                                    Text(event.startDate, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if let error = calendar.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}

struct MusicModuleView: View {
    @ObservedObject var music: MusicService
    var body: some View {
        VStack(spacing: 12) {
            if !music.isConnected {
                Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.mint)
                Text("Your music, one gesture away").font(.headline)
                HStack {
                    Button("Apple Music") { music.connect(to: .appleMusic) }
                    Button("Spotify") { music.connect(to: .spotify) }
                }
            } else if let track = music.track {
                HStack(spacing: 14) {
                    Group {
                        if let artwork = music.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                        } else { Image(systemName: "music.note").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.08)) }
                    }.frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.headline).lineLimit(1)
                        Text(track.artist).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                if track.duration > 0 {
                    Slider(value: Binding(get: { min(track.duration, max(0, track.position)) }, set: { music.seek(to: $0) }), in: 0...max(1, track.duration)).accessibilityLabel("Playback position")
                }
                HStack(spacing: 28) {
                    Button { music.previous() } label: { Image(systemName: "backward.fill") }
                    Button { music.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title2) }
                    Button { music.next() } label: { Image(systemName: "forward.fill") }
                }.buttonStyle(.plain)
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: { music.volume }, set: { music.setVolume($0) }), in: 0...1).accessibilityLabel("Player volume")
                    Image(systemName: "speaker.wave.3.fill")
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Open your player and choose a song.").foregroundStyle(.secondary)
                Button("Disconnect") { music.disconnect() }
            }
            if let error = music.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
        }
    }
}

struct SystemModuleView: View {
    @ObservedObject var system: SystemStatusService
    var body: some View {
        VStack(spacing: 12) {
            metric("CPU", value: system.cpuUsage.formatted(.percent.precision(.fractionLength(0))), symbol: "cpu")
            metric("Memory", value: ByteCountFormatter.string(fromByteCount: Int64(system.memoryUsedBytes), countStyle: .memory), symbol: "memorychip")
            if let battery = system.batteryLevel { metric("Battery", value: battery.formatted(.percent.precision(.fractionLength(0))), symbol: system.isCharging ? "battery.100.bolt" : "battery.100") }
            metric("Network", value: ByteCountFormatter.string(fromByteCount: Int64(system.networkBytesPerSecond), countStyle: .file) + "/s", symbol: "network")
            if let volume = system.outputVolume {
                HStack {
                    Image(systemName: "speaker.wave.2")
                    Slider(value: Binding(get: { volume }, set: { system.setOutputVolume($0) }), in: 0...1).accessibilityLabel("System volume")
                }
            }
        }
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.callout)
    }
}
