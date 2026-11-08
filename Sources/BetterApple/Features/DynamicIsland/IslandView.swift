import SwiftUI
import BetterAppleCore

@MainActor
struct IslandActivitySources {
    let timer: TimerService
    let music: MusicService
    let system: SystemStatusService
    let calendar: CalendarService
    let calculator: CalculatorService
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: IslandState
    let registry: IslandModuleRegistry
    let sources: IslandActivitySources
    let pin: () -> Void
    let hover: (Bool) -> Void
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var appearance: IslandAppearance { model.settings.island.visual }
    private var radius: CGFloat { state.expanded ? appearance.cornerRadius : min(appearance.cornerRadius, model.settings.island.minimal ? 6 : model.settings.island.height / 2) }
    var body: some View {
        VStack(spacing: 0) {
            if state.expanded {
                HStack {
                    Label(state.selected.title, systemImage: "circle.lefthalf.filled").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: pin) { Image(systemName: state.pinned ? "pin.fill" : "pin") }
                        .foregroundStyle(state.pinned ? appearance.accent.color : .secondary)
                        .help(state.pinned ? "Unpin Island" : "Keep Island open")
                        .accessibilityLabel(state.pinned ? "Unpin Island" : "Keep Island open")
                        .accessibilityAddTraits(state.pinned ? .isSelected : [])
                    Button(action: toggle) { Image(systemName: "chevron.up") }.help("Collapse Island").accessibilityLabel("Collapse Island")
                }.buttonStyle(.plain).padding(.bottom, 12)
                HStack(spacing: 6) {
                    ForEach(model.settings.island.modules) { module in
                        Button { state.selected = module } label: {
                            VStack(spacing: 5) {
                                Image(systemName: module.symbol).font(.system(size: 15, weight: .medium))
                                if appearance.showModuleLabels { Text(module.title).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7) }
                            }
                            .frame(maxWidth: .infinity).frame(height: appearance.showModuleLabels ? 44 : 32)
                            .background(state.selected == module ? appearance.accent.color.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(state.selected == module ? appearance.accent.color : .primary)
                        }.buttonStyle(.plain).help(module.title).accessibilityLabel(module.title)
                            .accessibilityAddTraits(state.selected == module ? .isSelected : [])
                    }
                }.padding(.bottom, 14)
                registry.content(for: state.selected).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Button(action: toggle) {
                    Group {
                        if model.settings.island.minimal {
                            Capsule().fill(appearance.accent.color).frame(width: 28, height: 3)
                        } else if appearance.compactStatus {
                            IslandCompactContent(module: state.selected, timer: sources.timer, music: sources.music, system: sources.system, calendar: sources.calendar, calculator: sources.calculator, accent: appearance.accent.color)
                        } else {
                            HStack {
                                Image(systemName: state.selected.symbol).foregroundStyle(appearance.accent.color)
                                Spacer(minLength: 6)
                                Text("BetterApple").font(.system(size: 12, weight: .medium))
                                Spacer(minLength: 6)
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }.contentShape(Rectangle()).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).accessibilityLabel("Expand \(state.selected.title)")
            }
        }
        .padding(state.expanded ? 18 : (model.settings.island.minimal ? 2 : 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IslandSurface(appearance: appearance, radius: radius))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .tint(appearance.accent.color)
        .preferredColorScheme(appearance.theme.colorScheme)
        .onHover(perform: hover)
        .onExitCommand { state.pinned = false; state.expanded = false }
        .animation(reduceMotion || appearance.animationDuration == 0 ? nil : .easeInOut(duration: appearance.animationDuration), value: state.expanded)
    }
}

private struct IslandCompactContent: View {
    let module: ModuleID
    @ObservedObject var timer: TimerService
    @ObservedObject var music: MusicService
    @ObservedObject var system: SystemStatusService
    @ObservedObject var calendar: CalendarService
    @ObservedObject var calculator: CalculatorService
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: module.symbol).foregroundStyle(accent)
            Group {
                switch module {
                case .timer:
                    if timer.isRunning || timer.isPaused {
                        Text(Duration.seconds(timer.remaining).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                        if timer.isPaused { Image(systemName: "pause.fill").foregroundStyle(.secondary) }
                    } else { Text(timer.didComplete ? "Timer complete" : "Set a timer") }
                case .music: Text(music.track?.title ?? "Connect a player")
                case .calendar: Text(calendar.events.first?.title ?? Date.now.formatted(.dateTime.month(.abbreviated).day()))
                case .calculator: Text(calculator.expression.isEmpty ? "Quick calculation" : calculator.resultText)
                case .system: Text("CPU \(system.cpuUsage.formatted(.percent.precision(.fractionLength(0))))").monospacedDigit()
                }
            }.font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}
