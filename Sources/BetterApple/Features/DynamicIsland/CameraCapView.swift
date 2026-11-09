import SwiftUI

/// Inward shoulders connect the notch to the display edge; the bottom curves
/// disappear while expanded so cap and body form one continuous silhouette.
struct NotchCapShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let shoulder = min(12, rect.width / 4, rect.height / 2)
        let radius = min(max(0, bottomRadius), max(0, (rect.width - shoulder * 2) / 2), max(0, rect.height - shoulder))
        let left = rect.minX + shoulder, right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + shoulder), control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - radius), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct CameraCapView: View {
    @ObservedObject var state: IslandState
    let cameraWidth: CGFloat
    let hover: (Bool) -> Void
    let expand: () -> Void

    init(state: IslandState, cameraWidth: CGFloat = 185,
         hover: @escaping (Bool) -> Void, expand: @escaping () -> Void) {
        self.state = state
        self.cameraWidth = cameraWidth
        self.hover = hover
        self.expand = expand
    }

    private var showsPlayback: Bool { !state.expanded && state.compactMusicTitle != nil }

    var body: some View {
        Button(action: expand) {
            GeometryReader { geometry in
                ZStack {
                    NotchCapShape(bottomRadius: state.expanded ? 0 : 10)
                        .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
                    if showsPlayback {
                        let artworkSize = min(24, max(0, geometry.size.height - 8))
                        HStack(spacing: 0) {
                            Group {
                                if let artwork = state.compactArtwork {
                                    Image(nsImage: artwork).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "music.note")
                                        .font(.system(size: min(13, artworkSize * 0.6), weight: .medium))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .foregroundStyle(.white.opacity(0.85))
                                        .background(.white.opacity(0.09))
                                }
                            }
                            .frame(width: artworkSize, height: artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .frame(width: 44)
                            // This gap is the actual physical cutout width on MacBooks.
                            Color.clear.frame(width: max(0, cameraWidth))
                            Image(systemName: state.compactMusicPlaying ? "waveform" : "pause.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(state.compactMusicPlaying ? Color.green.opacity(0.9) : Color.white.opacity(0.65))
                                .frame(width: 44)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(NotchCapShape(bottomRadius: state.expanded ? 0 : 10))
            }
        }
        .buttonStyle(.plain).focusable(false)
        .accessibilityLabel("Open Dynamic Island notch")
        .accessibilityValue(showsPlayback ? "\(state.compactMusicTitle ?? "") · \(state.compactMusicPlaying ? "Playing" : "Paused")" : "")
        .help(showsPlayback ? state.compactMusicTitle ?? "Open Dynamic Island" : "Open Dynamic Island")
        .onHover(perform: hover)
    }
}
