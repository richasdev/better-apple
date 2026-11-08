import SwiftUI
import AppKit

struct MusicModuleView: View {
    @ObservedObject var music: MusicService
    @State private var seekPosition: Double?
    @State private var scrubbing = false
    @State private var scrubTrackIdentity: String?
    @State private var seekExpiry: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceMotionDisabled) private var localMotionDisabled
    private var reduceMotion: Bool { systemReduceMotion || localMotionDisabled }
    private var trackIdentity: String? {
        guard let track = music.track else { return nil }
        return [track.title, track.artist, track.album, String(track.duration)].joined(separator: "\u{001F}")
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
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
                        Label(music.isConnected ? music.selectedPlayer.title : "Connect player", systemImage: "music.note").font(.caption)
                    }.menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel(music.isConnected ? "Connected player: \(music.selectedPlayer.title)" : "Connect music player")
                    Spacer()
                    Button { music.openPlayer() } label: { Image(systemName: "arrow.up.right").frame(width: 16, height: 16) }
                        .buttonStyle(SurfaceButtonStyle()).help("Open \(music.selectedPlayer.title)")
                        .accessibilityLabel("Open \(music.selectedPlayer.title)")
                }
                Group {
                    if !music.isConnected {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note").font(.system(size: 25)).foregroundStyle(.tint).accessibilityHidden(true)
                            Text("Your music, within reach").font(.headline)
                            Text("Open a player, then connect above. macOS may ask for Automation access.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Open \(music.selectedPlayer.title)") { music.openPlayer() }
                        }.frame(maxWidth: .infinity).padding(.vertical, 4)
                    } else if let track = music.track {
                        playback(track)
                    } else {
                        VStack(spacing: 8) {
                            Label("Ready when you are", systemImage: "music.note.list").font(.headline)
                            Text("Choose a song in \(music.selectedPlayer.title).").font(.caption).foregroundStyle(.secondary)
                            Button("Open player") { music.openPlayer() }
                        }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                }.transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                if let error = music.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity)
                .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: music.isConnected)
        }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .onChange(of: music.track?.position) { _, position in
                guard !scrubbing, let target = seekPosition, let position else { return }
                if abs(position - target) <= (music.track?.isPlaying == true ? 2.5 : 0.25) { clearPendingSeek() }
            }
            .onChange(of: trackIdentity) { _, _ in clearPendingSeek() }
            .onChange(of: music.errorMessage) { _, error in if error != nil { clearPendingSeek() } }
            .onChange(of: music.isConnected) { _, connected in if !connected { clearPendingSeek(); scrubbing = false; scrubTrackIdentity = nil } }
            .onDisappear { seekExpiry?.cancel(); seekExpiry = nil; scrubbing = false; scrubTrackIdentity = nil; seekPosition = nil }
    }
    private func playback(_ track: MusicTrack) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Group {
                    if let artwork = music.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                    else { Image(systemName: "music.note").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(.primary.opacity(0.06)) }
                }.frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.headline).lineLimit(1).help(track.title)
                    Text(track.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    if !track.album.isEmpty { Text(track.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                }.accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            if track.duration > 0 {
                VStack(spacing: 2) {
                    Slider(value: Binding(get: { min(track.duration, max(0, seekPosition ?? track.position)) }, set: { seekPosition = $0 }), in: 0...max(1, track.duration), onEditingChanged: { editing in
                        if editing { scrubbing = true; scrubTrackIdentity = trackIdentity }
                        else {
                            if scrubTrackIdentity == trackIdentity, let seekPosition { commitSeek(to: seekPosition) }
                            scrubbing = false; scrubTrackIdentity = nil
                        }
                    }).accessibilityLabel("Playback position")
                        .accessibilityValue("\(durationText(seekPosition ?? track.position)) of \(durationText(track.duration))")
                        .accessibilityHint("Use arrow keys to seek five seconds.")
                        .onKeyPress(.leftArrow) { seek(by: -5, track: track); return .handled }
                        .onKeyPress(.rightArrow) { seek(by: 5, track: track); return .handled }
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: seek(by: 5, track: track)
                            case .decrement: seek(by: -5, track: track)
                            @unknown default: break
                            }
                        }
                    HStack {
                        Text(durationText(seekPosition ?? track.position))
                        Spacer()
                        Text(durationText(track.duration))
                    }.font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            HStack(spacing: 18) {
                Button { music.previous() } label: { Image(systemName: "backward.fill").frame(width: 20, height: 24) }
                    .buttonStyle(SurfaceButtonStyle()).accessibilityLabel("Previous track").help("Previous track")
                Button { music.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 26, height: 28) }
                    .buttonStyle(SurfaceButtonStyle(prominent: true)).accessibilityLabel(track.isPlaying ? "Pause" : "Play").help(track.isPlaying ? "Pause" : "Play")
                Button { music.next() } label: { Image(systemName: "forward.fill").frame(width: 20, height: 24) }
                    .buttonStyle(SurfaceButtonStyle()).accessibilityLabel("Next track").help("Next track")
            }.frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").accessibilityHidden(true)
                Slider(value: Binding(get: { music.volume }, set: { music.setVolume($0) }), in: 0...1).accessibilityLabel("Player volume")
                Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func seek(by delta: Double, track: MusicTrack) {
        let target = min(track.duration, max(0, (seekPosition ?? track.position) + delta))
        commitSeek(to: target)
    }
    private func commitSeek(to target: Double) {
        seekPosition = target
        music.seek(to: target)
        seekExpiry?.cancel()
        // A single cancellable acknowledgement deadline, never another player poll.
        seekExpiry = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            seekPosition = nil; seekExpiry = nil
        }
    }
    private func clearPendingSeek() {
        seekExpiry?.cancel(); seekExpiry = nil; seekPosition = nil
    }
    private func durationText(_ value: TimeInterval) -> String {
        let seconds = max(0, value.rounded(.down))
        return Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
