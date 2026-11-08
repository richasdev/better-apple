import SwiftUI
import AppKit
import BetterAppleCore

struct CalendarModuleView: View {
    @ObservedObject var calendar: CalendarService
    @State private var displayDate = Date.now
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceMotionDisabled) private var localMotionDisabled
    private var reduceMotion: Bool { systemReduceMotion || localMotionDisabled }
    private var hasAccess: Bool { calendar.authorizationStatus == .fullAccess }
    private var accessDenied: Bool { calendar.authorizationStatus == .denied || calendar.authorizationStatus == .restricted }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(displayDate, format: .dateTime.weekday(.wide).month().day()).font(.headline)
                    Spacer()
                    Button { calendar.openCalendar() } label: { Image(systemName: "arrow.up.right").frame(width: 16, height: 16) }
                        .buttonStyle(SurfaceButtonStyle()).help("Open Calendar").accessibilityLabel("Open Calendar")
                }
                Group {
                    if !hasAccess {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(accessDenied ? "Calendar access is off" : "Your next event, within reach", systemImage: accessDenied ? "calendar.badge.exclamationmark" : "calendar")
                                .font(.callout.weight(.medium))
                            Text(accessDenied ? "Allow BetterApple in Privacy & Security → Calendars to see upcoming events." : "Connect your calendar to see upcoming events. Your calendar stays on this Mac.")
                                .font(.caption).foregroundStyle(.secondary)
                            if accessDenied {
                                Button("Open Privacy Settings") { openCalendarPrivacy() }
                            } else {
                                Button("Connect Calendar") { Task { await calendar.requestAccess() } }.buttonStyle(.borderedProminent)
                            }
                        }
                    } else if calendar.events.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Nothing coming up", systemImage: "calendar.badge.checkmark").font(.callout.weight(.medium))
                            Text("No events in the next seven days.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(calendar.events.prefix(12)) { event in
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2).fill(.tint).frame(width: 3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title).font(.callout.weight(.medium)).lineLimit(2)
                                        HStack(spacing: 5) {
                                            Text(event.startDate, format: .dateTime.month(.abbreviated).day())
                                            Text("·").accessibilityHidden(true)
                                            if event.isAllDay { Text("All day") }
                                            else { Text(event.startDate, format: .dateTime.hour().minute()) }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 9).accessibilityElement(children: .combine)
                            }
                        }
                    }
                }.transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                if let error = calendar.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: hasAccess)
        }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .onAppear { displayDate = .now }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in displayDate = .now }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in displayDate = .now }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in displayDate = .now }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in displayDate = .now }
    }
    private func openCalendarPrivacy() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SystemModuleView: View {
    @ObservedObject var system: SystemStatusService
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceMotionDisabled) private var localMotionDisabled
    private var reduceMotion: Bool { systemReduceMotion || localMotionDisabled }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                metric("CPU", value: system.cpuUsage.formatted(.percent.precision(.fractionLength(0))), symbol: "cpu")
                metric("Memory", value: ByteCountFormatter.string(fromByteCount: Int64(system.memoryUsedBytes), countStyle: .memory), symbol: "memorychip")
                if let battery = system.batteryLevel {
                    metric(system.isCharging ? "Charging" : "Battery", value: battery.formatted(.percent.precision(.fractionLength(0))), symbol: system.isCharging ? "battery.100.bolt" : "battery.100")
                }
                metric("Network", value: ByteCountFormatter.string(fromByteCount: Int64(system.networkBytesPerSecond), countStyle: .file) + "/s", symbol: "network")
                if let volume = system.outputVolume {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2").frame(width: 18).foregroundStyle(.secondary).accessibilityHidden(true)
                        Slider(value: Binding(get: { volume }, set: { system.setOutputVolume($0) }), in: 0...1).accessibilityLabel("System volume")
                        Text(volume, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    }
                } else {
                    Text("Volume is managed by the current audio device.").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity).padding(.vertical, 2)
        }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: value)
        }.font(.callout).accessibilityElement(children: .combine)
    }
}
