import SwiftUI
import AppKit
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
    let open: () -> Void
    let close: () -> Void
    let select: (ModuleID) -> Void
    let keyboardActive: () -> Bool
    @Namespace private var selectionAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var inheritedScheme
    private var cameraMode: Bool { model.settings.island.placementMode == .camera }
    private var appearance: IslandAppearance {
        var visual = model.settings.island.visual
        if cameraMode {
            visual.theme = .dark; visual.material = .solid; visual.opacity = 1; visual.borderVisible = false
        }
        return visual
    }
    private var motionDisabled: Bool { reduceMotion || appearance.animationDuration == 0 }
    private var radius: CGFloat { state.expanded ? appearance.cornerRadius : min(appearance.cornerRadius, model.settings.island.minimal ? 6 : model.settings.island.height / 2) }
    var body: some View {
        ZStack(alignment: .top) {
            if state.expanded || state.expandedContentVisible {
                if state.connectionNoticeCompact, let notice = state.connectionNotice {
                    IslandConnectionBanner(notice: notice)
                        .padding(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(state.expandedContentVisible ? 1 : 0)
                        .contentShape(Rectangle()).onTapGesture(perform: open)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Open Dynamic Island tools")
                } else {
                VStack(spacing: 0) {
                if let notice = state.connectionNotice {
                    IslandConnectionBanner(notice: notice).padding(.bottom, 12)
                }
                HStack {
                    Label(state.selected.title, systemImage: "circle.lefthalf.filled").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: pin) { Image(systemName: state.pinned ? "pin.fill" : "pin") }
                        .foregroundStyle(state.pinned ? appearance.accent.color : .secondary)
                        .help(state.pinned ? "Unpin Island" : "Keep Island open")
                        .accessibilityLabel(state.pinned ? "Unpin Island" : "Keep Island open")
                        .accessibilityAddTraits(state.pinned ? .isSelected : [])
                    Button(action: toggle) { Image(systemName: "chevron.up") }.help("Collapse Island").accessibilityLabel("Collapse Island")
                }.buttonStyle(SurfaceButtonStyle(accent: appearance.accent.color)).padding(.bottom, 10)
                HStack(spacing: 6) {
                    ForEach(model.settings.island.modules) { module in
                        Button { select(module) } label: {
                            VStack(spacing: 5) {
                                Image(systemName: module.symbol).font(.system(size: 15, weight: .medium))
                                if appearance.showModuleLabels { Text(module.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8) }
                            }
                            .frame(maxWidth: .infinity).frame(height: appearance.showModuleLabels ? 44 : 32)
                            .background {
                                if state.selected == module {
                                    RoundedRectangle(cornerRadius: 9).fill(appearance.accent.color.opacity(0.17))
                                        .matchedGeometryEffect(id: "moduleSelection", in: selectionAnimation)
                                }
                            }
                            .foregroundStyle(state.selected == module ? appearance.accent.color : .primary)
                        }.buttonStyle(SurfaceButtonStyle(accent: appearance.accent.color)).help(module.title).accessibilityLabel(module.title)
                            .accessibilityAddTraits(state.selected == module ? .isSelected : [])
                    }
                }.padding(.bottom, 12)
                    .animation(WorkspaceMotion.animation(reduceMotion: motionDisabled, duration: WorkspaceMotion.content), value: state.selected)
                registry.content(for: state.selected)
                    .environment(\.islandFocusRequest, keyboardActive() ? state.focusRequest : 0)
                    .id(state.selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(WorkspaceMotion.transition(reduceMotion: motionDisabled))
                    .animation(WorkspaceMotion.animation(reduceMotion: motionDisabled, duration: WorkspaceMotion.content), value: state.selected)
                }
                .padding(18)
                .transition(WorkspaceMotion.transition(reduceMotion: motionDisabled))
                .opacity(state.expandedContentVisible ? 1 : 0)
                .offset(y: state.expandedContentVisible || motionDisabled ? 0 : 4)
                .allowsHitTesting(state.expandedContentVisible)
                .accessibilityHidden(!state.expandedContentVisible)
                .animation(WorkspaceMotion.animation(reduceMotion: motionDisabled, duration: min(WorkspaceMotion.content, appearance.animationDuration)), value: state.connectionNotice?.id)
                }
            }
            if state.compactContentVisible {
                Button(action: open) {
                    Group {
                        if cameraMode {
                            Color.clear.contentShape(Rectangle())
                        } else if model.settings.island.minimal {
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
                    .padding(cameraMode ? 0 : (model.settings.island.minimal ? 2 : 10))
                    .transition(WorkspaceMotion.transition(reduceMotion: motionDisabled))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if cameraMode {
                if state.expanded || state.expandedContentVisible {
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                        bottomTrailingRadius: radius, topTrailingRadius: 0).fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
                }
            } else {
                IslandSurface(appearance: appearance, radius: radius)
                    .animation(WorkspaceMotion.animation(reduceMotion: motionDisabled, duration: appearance.animationDuration), value: state.expanded)
            }
        }
        .clipShape(IslandOutline(camera: cameraMode, radius: radius))
        .tint(appearance.accent.color)
        .accentColor(appearance.accent.color)
        .environment(\.workspaceMotionDisabled, motionDisabled)
        .preferredColorScheme(appearance.theme.colorScheme)
        .environment(\.colorScheme, appearance.theme.colorScheme ?? inheritedScheme)
        .foregroundStyle(.primary)
        .onHover(perform: hover)
        .onExitCommand(perform: close)
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
    @State private var currentDate = Date.now
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
                case .calendar: Text(calendar.events.first?.title ?? currentDate.formatted(.dateTime.month(.abbreviated).day()))
                case .calculator: Text(calculator.expression.isEmpty ? "Quick calculation" : calculator.resultText)
                case .system: Text("CPU \(system.cpuUsage.formatted(.percent.precision(.fractionLength(0))))").monospacedDigit()
                }
            }.font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .onAppear { currentDate = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in currentDate = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in currentDate = .now }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in currentDate = .now }
    }
}

private struct IslandOutline: Shape {
    let camera: Bool
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        if camera {
            return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                bottomTrailingRadius: radius, topTrailingRadius: 0).path(in: rect)
        }
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}

private struct IslandConnectionBanner: View {
    let notice: IslandConnectionNotice
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: notice.symbol).font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white).frame(width: 50).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.name).font(.system(size: 17, weight: .semibold)).lineLimit(1).foregroundStyle(.white)
                Label(notice.connected ? "Connected" : "Disconnected", systemImage: notice.connected ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(notice.connected ? Color.green : Color.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}
