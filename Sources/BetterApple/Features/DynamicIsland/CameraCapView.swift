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
    let hover: (Bool) -> Void
    let expand: () -> Void
    var body: some View {
        Button(action: expand) {
            NotchCapShape(bottomRadius: state.expanded ? 0 : 10)
                .fill(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(NotchCapShape(bottomRadius: state.expanded ? 0 : 10))
        }
        .buttonStyle(.plain).focusable(false)
        .accessibilityLabel("Open Dynamic Island notch")
        .onHover(perform: hover)
    }
}
