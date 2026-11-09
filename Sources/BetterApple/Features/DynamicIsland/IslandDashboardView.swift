import SwiftUI
import AppKit
import BetterAppleCore

/// A short, horizontal first level. Detailed tools remain one deliberate action away.
/// Every visible value comes from the same services used by the full tools.
struct IslandDashboardView: View {
    let sources: IslandActivitySources
    let modules: [ModuleID]
    let openModule: (ModuleID) -> Void
    let close: () -> Void
    let pinned: Bool
    let pin: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if modules.contains(.music) {
                    DashboardPlayerMenu(music: sources.music)
                } else {
                    Text("BetterApple").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    ForEach(modules) { module in
                        Button { openModule(module) } label: { Label(module.title, systemImage: module.symbol) }
                    }
                } label: {
                    Label("Tools", systemImage: "square.grid.2x2").font(.system(size: 10, weight: .medium))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Open a Dynamic Island tool")
                Button(action: pin) { Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 10)) }
                    .buttonStyle(SurfaceButtonStyle(accent: .white))
                    .foregroundStyle(pinned ? Color.white : Color.secondary)
                    .help(pinned ? "Unpin Island" : "Keep Island open")
                    .accessibilityLabel(pinned ? "Unpin Island" : "Keep Island open")
                    .accessibilityAddTraits(pinned ? .isSelected : [])
                Button(action: close) { Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(SurfaceButtonStyle(accent: .white)).foregroundStyle(.secondary)
                    .help("Collapse Island").accessibilityLabel("Collapse Island")
            }
            HStack(alignment: .center, spacing: 14) {
                if modules.contains(.music) {
                    DashboardMusic(music: sources.music, open: { openModule(.music) })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if modules.contains(.music) && modules.contains(.calendar) {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 2)
                }
                if modules.contains(.calendar) {
                    DashboardCalendar(calendar: sources.calendar, open: { openModule(.calendar) })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !modules.contains(.music) && !modules.contains(.calendar) {
                    HStack(spacing: 8) {
                        ForEach(modules.prefix(4)) { module in
                            Button { openModule(module) } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: module.symbol).font(.system(size: 18))
                                    Text(module.title).font(.system(size: 10)).lineLimit(1)
                                }.frame(maxWidth: .infinity, minHeight: 55)
                            }.buttonStyle(SurfaceButtonStyle(accent: .white))
                        }
                    }.frame(maxWidth: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 12)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

private struct DashboardPlayerMenu: View {
    @ObservedObject var music: MusicService
    @State private var showingStatus = false
    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(music.availablePlayers) { player in
                    Button(player.title) { music.connect(to: player) }
                }
                if music.isConnected || music.isConnecting {
                    Divider()
                    Button("Disconnect") { music.disconnect() }
                }
            } label: {
                Label(music.selectedPlayer.title, systemImage: "music.note")
                    .font(.system(size: 10, weight: .medium)).lineLimit(1)
            }.menuStyle(.borderlessButton).frame(maxWidth: 170, alignment: .leading)
                .accessibilityLabel("Choose music player. Selected: \(music.selectedPlayer.title)")
            if music.isConnecting {
                ProgressView().controlSize(.mini).accessibilityLabel("Connecting to player")
            }
            if music.errorMessage != nil || music.connectionHelp != nil {
                Button { showingStatus.toggle() } label: {
                    Image(systemName: music.errorMessage == nil ? "info.circle" : "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(music.errorMessage == nil ? Color.secondary : .orange)
                }.buttonStyle(.plain).help("Player connection details")
                    .accessibilityLabel("Player connection details")
                    .popover(isPresented: $showingStatus) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let error = music.errorMessage { Text(error).foregroundStyle(.orange) }
                            if let help = music.connectionHelp { Text(help).foregroundStyle(.secondary) }
                            Button("Open \(music.selectedPlayer.title)") { music.openPlayer() }
                        }.font(.callout).padding(16).frame(width: 290)
                            .onExitCommand { showingStatus = false }
                    }
            }
        }
        .onChange(of: music.selectedPlayer) { _, _ in showingStatus = false }
        .onDisappear { showingStatus = false }
    }
}

private struct DashboardMusic: View {
    @ObservedObject var music: MusicService
    let open: () -> Void
    private var subtitle: String {
        if let track = music.track, !track.artist.isEmpty { return track.artist }
        return music.isConnected ? music.selectedPlayer.title : "Choose a player above"
    }
    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                Group {
                    if let artwork = music.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.07))
                    }
                }.frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).help("Open music controls").accessibilityLabel("Open music controls")
            VStack(alignment: .leading, spacing: 3) {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.track?.title ?? (music.isConnected ? "Nothing playing" : "Your music, here"))
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help(music.track?.title ?? "Open music controls")
                HStack(spacing: 3) {
                    transport("backward.fill", label: "Previous track", action: music.previous)
                    transport(music.track?.isPlaying == true ? "pause.fill" : "play.fill", label: music.track?.isPlaying == true ? "Pause" : "Play", action: music.playPause)
                    transport("forward.fill", label: "Next track", action: music.next)
                }.disabled(!music.isConnected || music.track == nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func transport(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14, height: 16) }
            .buttonStyle(SurfaceButtonStyle(accent: .white)).help(label).accessibilityLabel(label)
    }
}

private struct DashboardCalendar: View {
    @ObservedObject var calendar: CalendarService
    let open: () -> Void
    @State private var date = Date.now
    private var week: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: open) {
                HStack(spacing: 9) {
                    Text(date, format: .dateTime.month(.abbreviated)).font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 1) {
                        ForEach(week, id: \.self) { day in
                            let today = Calendar.current.isDate(day, inSameDayAs: date)
                            VStack(spacing: 3) {
                                Text(day, format: .dateTime.weekday(.narrow)).font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary)
                                Text(day, format: .dateTime.day()).font(.system(size: 10, weight: today ? .bold : .medium))
                                    .foregroundStyle(today ? Color.white : Color.secondary)
                                    .frame(width: 20, height: 20)
                                    .background(today ? Color.accentColor : .clear, in: Circle())
                            }.accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).help("Open calendar details")
                .accessibilityLabel("Calendar week. Open calendar details")
                .accessibilityValue(date.formatted(date: .complete, time: .omitted))
            if calendar.authorizationStatus == .fullAccess {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let event = calendar.events.first {
                            Text(event.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(event.startDate, format: .dateTime.month(.abbreviated).day())
                                if event.isAllDay { Text("· All day") }
                                else { Text(event.startDate, format: .dateTime.hour().minute()) }
                            }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Label("Nothing coming up", systemImage: "calendar.badge.checkmark")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help("Open upcoming events")
            } else if calendar.authorizationStatus == .notDetermined {
                Button("Connect Calendar") { Task { await calendar.requestAccess() } }
                    .font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Allow Calendar access to show upcoming events")
            } else {
                Button(action: open) {
                    Label("Calendar access is off", systemImage: "lock").font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Open calendar permission details")
            }
        }
        .onAppear { date = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in date = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in date = .now }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in date = .now }
    }
}
