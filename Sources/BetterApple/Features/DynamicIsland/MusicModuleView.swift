import SwiftUI
import AppKit

struct MusicModuleView: View {
    @ObservedObject var music: MusicService
    @State private var seekPosition: Double?
    @State private var scrubbing = false
    @State private var scrubTrackIdentity: String?
    @State private var seekExpiry: Task<Void, Never>?
    @State private var showingConnectionHelp = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceMotionDisabled) private var localMotionDisabled
    private var reduceMotion: Bool { systemReduceMotion || localMotionDisabled }
    private var trackIdentity: String? {
        guard let track = music.track else { return nil }
        return [track.title, track.artist, track.album, String(track.duration)].joined(separator: "\u{001F}")
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                HStack {
                    Menu {
                        ForEach(music.availablePlayers) { player in
                            Button(player.title) { music.connect(to: player) }
                        }
                        if music.isConnected || music.isConnecting {
                            Divider()
                            Button("Reconnect") { music.connect(to: music.selectedPlayer) }
                            Button("Disconnect") { music.disconnect() }
                        }
                    } label: {
                        Label(music.selectedPlayer.title, systemImage: "music.note").font(.caption).lineLimit(1)
                    }.menuStyle(.borderlessButton).frame(maxWidth: 130, alignment: .leading)
                        .accessibilityLabel(music.isConnected ? "Connected player: \(music.selectedPlayer.title)" : "Connect music player")
                    Spacer(minLength: 4)
                    if music.isConnecting { ProgressView().controlSize(.mini).accessibilityLabel("Connecting to player") }
                    if music.isConnected {
                        Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                        Slider(value: Binding(get: { music.volume }, set: { music.setVolume($0) }), in: 0...1)
                            .frame(width: 70).controlSize(.mini).accessibilityLabel("Player volume")
                    }
                    Button { music.openPlayer() } label: { Image(systemName: "arrow.up.right").frame(width: 16, height: 16) }
                        .buttonStyle(SurfaceButtonStyle()).help("Open \(music.selectedPlayer.title)")
                        .accessibilityLabel("Open \(music.selectedPlayer.title)")
                }
                Group {
                    if !music.isConnected {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(music.isConnecting ? "Connecting…" : "Choose your player above").font(.subheadline.weight(.medium))
                            Text("Apple Music, Spotify or YouTube. macOS may ask for Automation access.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if let help = music.connectionHelp {
                                Button("Browser setup…") { showingConnectionHelp = true }
                                    .font(.caption).buttonStyle(.link)
                                    .popover(isPresented: $showingConnectionHelp) {
                                        VStack(alignment: .leading, spacing: 9) {
                                            Text("Connect \(music.selectedPlayer.title)").font(.headline)
                                            Text(help).font(.callout).fixedSize(horizontal: false, vertical: true)
                                        }.padding(16).frame(width: 290)
                                            .onExitCommand { showingConnectionHelp = false }
                                    }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if let track = music.track {
                        playback(track)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Ready when you are", systemImage: "music.note.list").font(.subheadline.weight(.medium))
                            Text("Choose a song in \(music.selectedPlayer.title).").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
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
            .onChange(of: music.isConnected) { _, connected in
                showingConnectionHelp = false
                if !connected { clearPendingSeek(); scrubbing = false; scrubTrackIdentity = nil }
            }
            .onChange(of: music.selectedPlayer) { _, _ in showingConnectionHelp = false }
            .onDisappear { seekExpiry?.cancel(); seekExpiry = nil; scrubbing = false; scrubTrackIdentity = nil; seekPosition = nil; showingConnectionHelp = false }
    }
    private func playback(_ track: MusicTrack) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                Group {
                    if let artwork = music.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                    else { Image(systemName: "music.note").font(.title3).frame(maxWidth: .infinity, maxHeight: .infinity).background(.primary.opacity(0.06)) }
                }.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).help(track.title)
                    Text(track.artist.isEmpty ? track.album : track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                HStack(spacing: 3) {
                    Button { music.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 11)).frame(width: 16, height: 24) }
                        .buttonStyle(SurfaceButtonStyle()).accessibilityLabel("Previous track").help("Previous track")
                    Button { music.playPause() } label: { Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .semibold)).frame(width: 20, height: 24) }
                        .buttonStyle(SurfaceButtonStyle(prominent: true)).accessibilityLabel(track.isPlaying ? "Pause" : "Play").help(track.isPlaying ? "Pause" : "Play")
                    Button { music.next() } label: { Image(systemName: "forward.fill").font(.system(size: 11)).frame(width: 16, height: 24) }
                        .buttonStyle(SurfaceButtonStyle()).accessibilityLabel("Next track").help("Next track")
                }
            }
            if track.duration > 0 {
                HStack(spacing: 6) {
                    Text(durationText(seekPosition ?? track.position)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: Binding(get: { min(track.duration, max(0, seekPosition ?? track.position)) }, set: { seekPosition = $0 }), in: 0...max(1, track.duration), onEditingChanged: { editing in
                        if editing { scrubbing = true; scrubTrackIdentity = trackIdentity }
                        else {
                            if scrubTrackIdentity == trackIdentity, let seekPosition { commitSeek(to: seekPosition) }
                            scrubbing = false; scrubTrackIdentity = nil
                        }
                    }).controlSize(.mini).accessibilityLabel("Playback position")
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
                    Text(durationText(track.duration)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
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
