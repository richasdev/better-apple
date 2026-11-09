import AppKit
import SwiftUI

/// Native SwiftUI path/raster diagnostic, not a screenshot of the physical display.
@main struct NotchShapeSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let capRect = CGRect(x: 0, y: 0, width: 209, height: 36)
        let compact = NotchCapShape(bottomRadius: 10).path(in: capRect)
        assert(compact.contains(CGPoint(x: 104, y: 1)))
        assert(compact.contains(CGPoint(x: 13, y: 8)))
        assert(!compact.contains(CGPoint(x: 2, y: 8)))
        assert(!compact.contains(CGPoint(x: 207, y: 8)))
        assert(!compact.contains(CGPoint(x: 13, y: 35)))
        assert(compact.contains(CGPoint(x: 23, y: 35)))
        assert(compact.contains(CGPoint(x: 104, y: 35)))
        let expanded = NotchCapShape(bottomRadius: 0).path(in: capRect)
        assert(expanded.contains(CGPoint(x: 13, y: 35)))
        assert(expanded.contains(CGPoint(x: 196, y: 35)))
        assert(!expanded.contains(CGPoint(x: 11, y: 35)))
        var animated = NotchCapShape(bottomRadius: 10)
        animated.animatableData = AnimatablePair(0, 0)
        assert(animated.path(in: capRect).contains(CGPoint(x: 13, y: 35)))
        // Collapsed inset: the bottom strip stays undrawn (invisible hover margin).
        let inset = NotchCapShape(bottomRadius: 10, bottomInset: 4).path(in: capRect).boundingRect
        assert(abs(inset.maxY - (capRect.maxY - 4)) < 0.01 && abs(inset.minY - capRect.minY) < 0.01)
        let clamped = NotchCapShape(bottomRadius: 10, bottomInset: 999).path(in: capRect).boundingRect
        assert(clamped.height >= capRect.height / 2 - 0.01)
        let translatedRect = capRect.offsetBy(dx: -500, dy: 250)
        let translated = NotchCapShape(bottomRadius: 10).path(in: translatedRect)
        assert(translated.contains(CGPoint(x: -396, y: 251)))
        assert(!translated.contains(CGPoint(x: -498, y: 258)))
        for radius in [CGFloat(-10), 0, 10, 999] {
            let tiny = CGRect(x: -30, y: 50, width: 8, height: 4)
            let bounds = NotchCapShape(bottomRadius: radius).path(in: tiny).boundingRect
            assert(!bounds.isNull && !bounds.isInfinite)
            assert(bounds.minX >= tiny.minX && bounds.maxX <= tiny.maxX)
            assert(bounds.minY >= tiny.minY && bounds.maxY <= tiny.maxY)
        }
        let bodyRect = CGRect(x: 0, y: 0, width: 440, height: 260)
        let lowerBody = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 22,
            bottomTrailingRadius: 22, topTrailingRadius: 0).path(in: bodyRect)
        assert(lowerBody.contains(CGPoint(x: 1, y: 1)))
        assert(!lowerBody.contains(CGPoint(x: 1, y: 259)))
        assert(lowerBody.contains(CGPoint(x: 220, y: 259)))
        // Four points overlap: both real SwiftUI paths cover the shared central seam.
        let wideCap = NotchCapShape(bottomRadius: 0).path(in: CGRect(x: 0, y: 0, width: 464, height: 36))
        for x in stride(from: CGFloat(13), through: 451, by: 11) {
            assert(wideCap.contains(CGPoint(x: x, y: 34)))
            assert(lowerBody.contains(CGPoint(x: x - 12, y: 2)))
        }

        let board = HStack(alignment: .top, spacing: 32) {
            VStack(spacing: 16) {
                surface(expanded: false).frame(width: 240, height: 300, alignment: .top)
                Text("Compact · body 185 pt / cap 209 pt").font(.system(size: 12))
            }
            VStack(spacing: 16) {
                surface(expanded: true).frame(width: 480, height: 300, alignment: .top)
                Text("Expanded · body 440 pt / cap 464 pt").font(.system(size: 12))
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .foregroundStyle(.black).background(.white)
        let renderer = ImageRenderer(content: board)
        renderer.scale = 2
        guard let rendered = renderer.cgImage else { fatalError("SwiftUI shape diagnostic did not render") }
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode native shape raster") }
        let destination = URL(fileURLWithPath: "/tmp/BetterApple-notch-shape.png")
        try png.write(to: destination)
        print("PASS: native NotchCapShape concave shoulders, compact/expanded lower corners, animatable radius, translated/tiny frames and continuous cap/body seam.")
        print("Diagnostic raster: \(destination.path) (offscreen SwiftUI, not physical GUI verification).")
    }

    @MainActor private static func surface(expanded: Bool) -> some View {
        let state = IslandState()
        state.expanded = expanded
        let bodyWidth: CGFloat = expanded ? 440 : 185
        return ZStack(alignment: .top) {
            if expanded {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22, topTrailingRadius: 0)
                    .fill(.black).frame(width: bodyWidth, height: 260).offset(y: 32)
            }
            CameraCapView(state: state, hover: { _ in }, expand: {})
                .frame(width: bodyWidth + 24, height: 36)
        }
        .frame(width: bodyWidth + 24, height: expanded ? 292 : 36, alignment: .top)
    }
}
