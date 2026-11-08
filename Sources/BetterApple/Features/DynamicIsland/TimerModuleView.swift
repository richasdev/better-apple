import SwiftUI

/// Validate the actual text draft, not the previous value of a numeric binding.
enum TimerDraftValidation {
    static func minutes(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let scanner = Scanner(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        scanner.locale = locale
        guard let value = scanner.scanDouble(), scanner.isAtEnd, value.isFinite, value >= 1.0 / 60, value <= 10080 else { return nil }
        return value
    }
    static func presetMinutes(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), (1...1440).contains(value) else { return nil }
        return value
    }
}

struct TimerModuleView: View {
    @ObservedObject var timer: TimerService
    @State private var minutesText = "5"
    @State private var newPresetText = "10"
    @State private var showingPreferences = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceMotionDisabled) private var localMotionDisabled
    private var reduceMotion: Bool { systemReduceMotion || localMotionDisabled }
    @Environment(\.islandFocusRequest) private var focusRequest
    @FocusState private var customDurationFocused: Bool
    private var customMinutes: Double? { TimerDraftValidation.minutes(minutesText) }
    private var validDuration: Bool { customMinutes != nil }
    private var phase: Int { timer.didComplete ? 3 : timer.isPaused ? 2 : timer.isRunning ? 1 : 0 }
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
                    Button { showingPreferences.toggle() } label: { Image(systemName: "slider.horizontal.3").frame(width: 16, height: 16) }
                        .buttonStyle(SurfaceButtonStyle()).help("Timer preferences").accessibilityLabel("Timer preferences")
                        .popover(isPresented: $showingPreferences) { preferencesContent }
                }
                Text(timerText).font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit().foregroundStyle(timer.didComplete ? .green : .primary)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: timerText)
                    .accessibilityLabel("Time remaining: \(timerText)")
                ProgressView(value: timer.progress)
                    .tint(timer.didComplete ? .green : timer.isPaused ? .orange : .accentColor)
                    .opacity(phase == 0 ? 0 : 1)
                    .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: timer.progress)
                    .accessibilityLabel("Timer progress")
                    .accessibilityHidden(phase == 0)
                Group {
                    if timer.didComplete {
                        HStack {
                            Label("Complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Again") { timer.restart() }.buttonStyle(.borderedProminent)
                            Button("Dismiss") { timer.dismissCompletion() }
                        }.font(.callout)
                    } else if !timer.isRunning && !timer.isPaused {
                        VStack(spacing: 10) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    ForEach(timer.presetMinutes, id: \.self) { value in
                                        Button("\(value)m") { timer.start(seconds: Double(value * 60)) }
                                            .contextMenu { Button("Remove preset", role: .destructive) { timer.removePreset(minutes: value) }.disabled(timer.presetMinutes.count <= 1) }
                                            .accessibilityLabel("Start a \(value) minute timer")
                                    }
                                }.padding(.vertical, 2)
                            }
                            HStack {
                                TextField("Minutes", text: $minutesText).textFieldStyle(.roundedBorder)
                                    .frame(width: 80).accessibilityLabel("Custom duration in minutes")
                                    .focused($customDurationFocused)
                                    .onSubmit(startCustomTimer)
                                Text("min").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Start", action: startCustomTimer).buttonStyle(.borderedProminent).disabled(!validDuration)
                            }
                            if !validDuration {
                                Text("Choose a duration from 1 second to 7 days.").font(.caption).foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        HStack {
                            Button(timer.isPaused ? "Resume" : "Pause") { if timer.isPaused { timer.resume() } else { timer.pause() } }
                                .buttonStyle(.borderedProminent)
                            Button("+1 min") { timer.extend(seconds: 60) }.disabled(timer.duration >= 604800)
                            Spacer()
                            Button("Cancel", role: .destructive) { timer.cancel() }
                        }
                    }
                }.transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
            }.frame(maxWidth: .infinity)
                .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: phase)
        }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .onChange(of: focusRequest, initial: true) { _, request in
                if request > 0 && !timer.isRunning && !timer.isPaused { customDurationFocused = true }
            }
    }
    private func startCustomTimer() {
        guard let minutes = customMinutes else { return }
        timer.start(seconds: minutes * 60)
    }
    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer preferences").font(.headline)
            TextField("Timer label", text: $timer.label).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Timer label")
            Picker("Completion sound", selection: $timer.completionSound) {
                ForEach(TimerCompletionSound.allCases) { sound in Text(sound.title).tag(sound) }
            }
            Divider()
            Text("Quick durations").font(.callout.weight(.medium))
            HStack {
                TextField("Minutes", text: $newPresetText).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Preset duration in minutes")
                    .onSubmit(addPreset)
                Text("min").foregroundStyle(.secondary)
                Button("Add", action: addPreset).disabled(!canAddPreset)
            }
            Text("Up to eight presets, 1–1,440 minutes. Right-click a duration to remove it. Running timers stop when BetterApple quits.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 300).onExitCommand { showingPreferences = false }
    }
    private var newPreset: Int? { TimerDraftValidation.presetMinutes(newPresetText) }
    private var canAddPreset: Bool {
        guard let minutes = newPreset else { return false }
        return (1...1440).contains(minutes) && !timer.presetMinutes.contains(minutes) && timer.presetMinutes.count < 8
    }
    private func addPreset() { if canAddPreset, let minutes = newPreset { timer.addPreset(minutes: minutes) } }
}
