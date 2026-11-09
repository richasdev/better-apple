import AppKit
import SwiftUI

struct DockModuleView: View {
    let module: DockModule
    @ObservedObject var manager: DockManager
    var body: some View {
        Group {
            switch module {
            case .apps: EmptyView()
            case .music:
                if let sources = manager.sources { DockMusicTile(service: sources.music) }
                else { unavailable }
            case .timer:
                if let sources = manager.sources { DockTimerTile(service: sources.timer, animationDuration: manager.preferences.animationDuration) }
                else { unavailable }
            case .battery:
                if let sources = manager.sources { DockBatteryTile(service: sources.system) }
                else { unavailable }
            case .note:
                VStack(alignment: .leading, spacing: 5) {
                    Label("Quick note", systemImage: module.symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if manager.note.isEmpty { Text("Write a quick note…").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.leading, 4).allowsHitTesting(false) }
                        TextEditor(text: $manager.note).font(.system(size: 12)).scrollContentBackground(.hidden)
                            .accessibilityLabel("Dock quick note")
                    }
                }
            }
        }
        .padding(12)
        .frame(width: module.tileWidth, height: DockModule.tileHeight, alignment: .leading)
    }
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(module.title, systemImage: module.symbol).font(.caption.weight(.medium))
            Text("Service unavailable").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DockMusicTile: View {
    @ObservedObject var service: MusicService
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if service.isConnected {
                HStack(spacing: 8) {
                    Group {
                        if let artwork = service.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.primary.opacity(0.06)) }
                    }.frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.track?.title ?? "No track playing").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(service.track?.artist ?? service.selectedPlayer.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 16) {
                    Button { service.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { service.playPause() } label: { Image(systemName: service.track?.isPlaying == true ? "pause.fill" : "play.fill") }.accessibilityLabel("Play or pause")
                    Button { service.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                    Spacer(minLength: 0)
                    Menu { Button("Disconnect") { service.disconnect() } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 15)
                }.font(.system(size: 11)).buttonStyle(.borderless)
            } else {
                Label("Music", systemImage: "music.note").font(.caption.weight(.medium))
                Menu {
                    ForEach(service.availablePlayers) { player in
                        Button("Connect \(player.title)") { service.connect(to: player) }
                    }
                } label: { Text("Connect a player").font(.system(size: 12)) }
                    .menuStyle(.borderlessButton)
                Text(service.errorMessage ?? "Open your player, then connect.")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).help(service.errorMessage ?? "Automation access is requested only when you connect.")
            }
        }
    }
}

private struct DockTimerTile: View {
    @ObservedObject var service: TimerService
    let animationDuration: Double
    @State private var draftMinutes = 25
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(service.label.isEmpty ? "Timer" : service.label, systemImage: "timer").font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            if service.isRunning || service.isPaused {
                HStack {
                    Text(Duration.seconds(max(0, service.remaining.rounded(.up))).formatted(.time(pattern: service.remaining >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                        .font(.system(size: 21, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(reduceMotion || animationDuration == 0 ? .identity : .numericText(countsDown: true))
                        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: min(WorkspaceMotion.quick, animationDuration)), value: Int(ceil(service.remaining)))
                    Spacer(minLength: 2)
                    Button { service.isPaused ? service.resume() : service.pause() } label: { Image(systemName: service.isPaused ? "play.fill" : "pause.fill") }.accessibilityLabel(service.isPaused ? "Resume timer" : "Pause timer")
                    Button { service.cancel() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel timer")
                }.buttonStyle(.borderless)
            } else if service.didComplete {
                HStack {
                    Label("Finished", systemImage: "checkmark.circle.fill").font(.caption)
                    Spacer(minLength: 0)
                    Button("Dismiss") { service.dismissCompletion() }.font(.caption)
                }
            } else {
                HStack(spacing: 9) {
                    Text(Duration.seconds(draftMinutes * 60).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(service.presetMinutes, id: \.self) { minutes in
                            Button("\(minutes) minutes") { draftMinutes = minutes }
                        }
                    } label: { Image(systemName: "slider.horizontal.3") }
                        .menuStyle(.borderlessButton).frame(width: 16).accessibilityLabel("Timer duration")
                    Button { service.start(seconds: Double(draftMinutes * 60)) } label: {
                        Image(systemName: "play.circle.fill").font(.system(size: 24))
                    }.buttonStyle(.borderless).accessibilityLabel("Start \(draftMinutes) minute timer")
                }
            }
        }
        .onAppear { if !service.presetMinutes.contains(draftMinutes) { draftMinutes = service.presetMinutes.first ?? 25 } }
        .onChange(of: service.presetMinutes) { _, minutes in
            if !minutes.contains(draftMinutes) { draftMinutes = minutes.first ?? 25 }
        }
    }
}

private struct DockBatteryTile: View {
    @ObservedObject var service: SystemStatusService
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Battery", systemImage: service.isCharging ? "battery.100percent.bolt" : "battery.100percent")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            if let level = service.batteryLevel {
                Text(level, format: .percent.precision(.fractionLength(0))).font(.system(size: 24, weight: .light)).monospacedDigit()
                if service.isCharging { Text("Charging").font(.system(size: 9)).foregroundStyle(.secondary) }
            } else { Text("No battery data").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
