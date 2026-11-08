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
    @ObservedObject var calculator: CalculatorService
    var compact = false
    @State private var showingHistory = false
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            TextField("(24 + 18) / 6", text: $calculator.expression)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: compact ? 17 : 21, design: .monospaced))
                .accessibilityLabel("Mathematical expression")
                .onSubmit { calculator.commit() }
            HStack {
                Text(calculator.resultText)
                    .font(.system(size: compact ? 29 : 34, weight: .medium, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                Spacer()
                Button { calculator.copyResult() } label: {
                    Image(systemName: calculator.copied ? "checkmark" : "doc.on.doc")
                }.disabled(calculator.errorMessage != nil || calculator.expression.isEmpty)
                    .help("Copy result").accessibilityLabel("Copy result")
                Button { showingHistory.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Calculation history").accessibilityLabel("Calculation history")
                    .popover(isPresented: $showingHistory) { historyContent }
            }
            if let message = calculator.errorMessage {
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if !compact {
                Text("+  −  ×  ÷  ^  %  ( )  ·  Return to save")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.hidden)
    }
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calculation history").font(.headline)
                Spacer()
                Button("Clear", role: .destructive) { calculator.clearHistory() }.disabled(calculator.history.isEmpty)
            }
            Toggle("Save calculations locally", isOn: $calculator.historyEnabled)
            Text("Keeps the last 30 calculations. Disabling clears saved history. Calculations are never sent anywhere.")
                .font(.caption).foregroundStyle(.secondary)
            if calculator.history.isEmpty {
                Text(calculator.historyEnabled ? "Press Return or copy a result to save it." : "History is off.")
                    .foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(calculator.history) { entry in
                            HStack {
                                Button {
                                    calculator.use(entry); showingHistory = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.expression).font(.system(.caption, design: .monospaced)).lineLimit(2)
                                        Text("= " + Calculator.formatted(entry.result)).font(.callout.weight(.medium))
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { calculator.removeHistory(id: entry.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).help("Remove calculation")
                            }.padding(8).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxHeight: 280)
            }
        }.padding(18).frame(width: 340)
    }
}

struct TimerModuleView: View {
    @ObservedObject var timer: TimerService
    @State private var minutes = 5.0
    @State private var newPreset = 10
    @State private var showingPreferences = false
    private var timerText: String {
        let seconds = max(0, timer.remaining.rounded(.up))
        return Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
    var body: some View {
        ScrollView {
        VStack(spacing: 10) {
            HStack {
                Text(timer.label.isEmpty ? "Timer" : timer.label).font(.caption.weight(.medium)).lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                if timer.isPaused { Label("Paused", systemImage: "pause.circle").font(.caption).foregroundStyle(.orange) }
                Button { showingPreferences.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Timer preferences").accessibilityLabel("Timer preferences")
                    .popover(isPresented: $showingPreferences) { preferencesContent }
            }
            Text(timerText).font(.system(size: 42, weight: .light, design: .rounded))
                .monospacedDigit().foregroundStyle(timer.didComplete ? .green : .primary)
            if timer.isRunning || timer.isPaused || timer.didComplete {
                ProgressView(value: timer.progress).tint(timer.didComplete ? .green : .accentColor)
            }
            if timer.didComplete {
                HStack {
                    Label("Complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Again") { timer.restart() }
                    Button("Dismiss") { timer.dismissCompletion() }
                }.font(.callout)
            } else if !timer.isRunning && !timer.isPaused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(timer.presetMinutes, id: \.self) { value in
                            Button("\(value)m") { timer.start(seconds: Double(value * 60)) }
                                .contextMenu { Button("Remove preset", role: .destructive) { timer.removePreset(minutes: value) }.disabled(timer.presetMinutes.count <= 1) }
                        }
                    }
                }
                HStack {
                    TextField("Minutes", value: $minutes, format: .number).textFieldStyle(.roundedBorder)
                        .frame(width: 70).accessibilityLabel("Custom duration in minutes")
                    Text("min").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Start") { timer.start(seconds: min(604800, max(1, minutes * 60))) }
                }
            } else {
                HStack {
                    Button(timer.isPaused ? "Resume" : "Pause") { if timer.isPaused { timer.resume() } else { timer.pause() } }
                    Button("+1 min") { timer.extend(seconds: 60) }
                    Spacer()
                    Button("Cancel", role: .destructive) { timer.cancel() }
                }
            }
        }.frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
    }
    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer preferences").font(.headline)
            TextField("Timer label", text: $timer.label).textFieldStyle(.roundedBorder)
            Picker("Completion sound", selection: $timer.completionSound) {
                ForEach(TimerCompletionSound.allCases) { sound in Text(sound.title).tag(sound) }
            }
            Divider()
            Text("Quick durations").font(.callout.weight(.medium))
            HStack {
                TextField("Minutes", value: $newPreset, format: .number).textFieldStyle(.roundedBorder)
                Text("min").foregroundStyle(.secondary)
                Button("Add") { timer.addPreset(minutes: newPreset) }
                    .disabled(!(1...1440).contains(newPreset) || timer.presetMinutes.contains(newPreset) || timer.presetMinutes.count >= 8)
            }
            Text("Up to eight presets, 1–1,440 minutes. Right-click a duration to remove it. Preferences persist; running timers stop when BetterApple quits.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 300)
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
    @State private var seekPosition: Double?
    @State private var scrubbing = false
    var body: some View {
        ScrollView {
        VStack(spacing: 10) {
            HStack {
                Menu {
                    ForEach(music.availablePlayers) { player in
                        Button(player.title) { music.connect(to: player) }
                    }
                    if music.isConnected {
                        Divider()
                        Button("Reconnect") { music.connect(to: music.selectedPlayer) }
                        Button("Disconnect") { music.disconnect() }
                    }
                } label: {
                    Label(music.isConnected ? music.selectedPlayer.title : "Connect player", systemImage: "music.note")
                        .font(.caption)
                }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button { music.openPlayer() } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.plain).help("Open \(music.selectedPlayer.title)")
            }
            if !music.isConnected {
                Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.tint)
                Text("Your music, one gesture away").font(.headline)
                Text("Open a player, then connect using the menu above. macOS may ask for Automation access.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if let track = music.track {
                HStack(spacing: 14) {
                    Group {
                        if let artwork = music.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                        } else {
                            Image(systemName: "music.note").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(.primary.opacity(0.06))
                        }
                    }.frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.headline).lineLimit(1)
                        Text(track.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        if !track.album.isEmpty { Text(track.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                if track.duration > 0 {
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { min(track.duration, max(0, seekPosition ?? track.position)) }, set: { seekPosition = $0 }), in: 0...max(1, track.duration), onEditingChanged: { editing in
                            scrubbing = editing
                            if !editing, let seekPosition { music.seek(to: seekPosition) }
                        }).accessibilityLabel("Playback position")
                        HStack {
                            Text(durationText(seekPosition ?? track.position))
                            Spacer()
                            Text(durationText(track.duration))
                        }.font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 28) {
                    Button { music.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { music.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title2) }.accessibilityLabel(track.isPlaying ? "Pause" : "Play")
                    Button { music.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                }.buttonStyle(.plain)
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: { music.volume }, set: { music.setVolume($0) }), in: 0...1).accessibilityLabel("Player volume")
                    Image(systemName: "speaker.wave.3.fill")
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Choose a song in \(music.selectedPlayer.title).").foregroundStyle(.secondary)
                Button("Open player") { music.openPlayer() }
            }
            if let error = music.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }
        }.scrollIndicators(.hidden)
        .onChange(of: music.track?.position) { _, _ in if !scrubbing { seekPosition = nil } }
        .onChange(of: music.track?.title) { _, _ in seekPosition = nil; scrubbing = false }
    }
    private func durationText(_ value: TimeInterval) -> String {
        Duration.seconds(max(0, value.rounded(.down))).formatted(.time(pattern: .minuteSecond))
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
