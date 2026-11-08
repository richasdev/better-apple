import Foundation
import CoreGraphics

/// Public NSScreen measurements expressed in the same global coordinate space.
public struct CameraScreenMetrics: Equatable, Sendable {
    public let screenFrame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaTop: Double
    public let auxiliaryLeft: CGRect?
    public let auxiliaryRight: CGRect?

    public init(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: Double = 0,
                auxiliaryLeft: CGRect? = nil, auxiliaryRight: CGRect? = nil) {
        self.screenFrame = screenFrame; self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop; self.auxiliaryLeft = auxiliaryLeft; self.auxiliaryRight = auxiliaryRight
    }
}

public struct IslandWindowLayout: Equatable, Sendable {
    public let frame: CGRect
    /// Actual interactive body, entirely below the cutout/menu band on notch displays.
    public let bodyFrame: CGRect
    /// Narrow camera cap/trigger. It does not span menu commands beside the camera.
    public let capFrame: CGRect?
    /// Reserved space above expanded controls. No content should be placed under the sensor.
    public let topInset: Double
    public let cameraWidth: Double
    public let cameraHeight: Double
    public let hasNotch: Bool
    public let anchored: Bool
}

public enum CameraIslandGeometry {
    public static func layout(screen metrics: CameraScreenMetrics, expanded: Bool,
                              expandedWidth: Double, expandedHeight: Double) -> IslandWindowLayout {
        let screen = metrics.screenFrame
        guard usable(screen) else {
            return .init(frame: .zero, bodyFrame: .zero, capFrame: nil, topInset: 0, cameraWidth: 0, cameraHeight: 0, hasNotch: false, anchored: true)
        }
        let safeTop = metrics.safeAreaTop.isFinite ? max(0, min(metrics.safeAreaTop, screen.height)) : 0
        let hasNotch = safeTop > 0
        let requestedWidth = expandedWidth.isFinite ? max(1, expandedWidth) : 420
        let requestedHeight = expandedHeight.isFinite ? max(1, expandedHeight) : 320
        let cameraGap = hasNotch ? cutoutGap(screen: screen, bandHeight: safeTop,
                                             left: metrics.auxiliaryLeft, right: metrics.auxiliaryRight) : nil
        // A safe-area inset can exist while auxiliary rectangles are unavailable.
        // In that case the width is an explicitly conservative visual fallback,
        // rather than a claim that an exact hardware cutout was discovered.
        let cameraWidth = hasNotch ? cameraGap?.width ?? min(180, max(0, screen.width - 8)) : 0
        let center = cameraGap?.midX ?? screen.midX
        if hasNotch {
            // AppKit may reserve a menu band one point taller than the physical
            // safe area. Honor both measurements so it need not relocate the body.
            let visible = usable(metrics.visibleFrame) ? metrics.visibleFrame.intersection(screen) : .null
            let band = usable(visible) ? max(safeTop, screen.maxY - visible.maxY) : safeTop
            let width = min(screen.width, expanded ? max(requestedWidth, cameraWidth + 32) : cameraWidth + 8)
            let height = min(screen.height, expanded ? band + requestedHeight : band + 4)
            let frame = CGRect(x: bounded(center - width / 2, screen.minX, screen.maxX - width),
                               y: screen.maxY - height, width: width, height: height)
            let capHeight = min(screen.height, band + 4)
            // Only validated auxiliary measurements justify a window in the menu band.
            // The real hardware is already black; a guessed cap would steal menu input.
            let cap = cameraGap.map { gap in
                CGRect(x: gap.minX, y: screen.maxY - capHeight, width: gap.width, height: capHeight)
            }
            let body = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(0, frame.height - band))
            return .init(frame: frame, bodyFrame: body, capFrame: cap, topInset: expanded ? min(band, height) : 0,
                         cameraWidth: cameraWidth, cameraHeight: safeTop, hasNotch: true, anchored: true)
        }
        // Displays without a physical cutout keep menu commands unobstructed.
        // Both states share a top anchor just below the visible menu-bar edge.
        let intersection = usable(metrics.visibleFrame) ? metrics.visibleFrame.intersection(screen) : .null
        let visible = usable(intersection) ? intersection : screen
        let top = max(visible.minY, min(screen.maxY, visible.maxY) - 2)
        let width = min(screen.width, expanded ? requestedWidth : 80)
        let height = min(max(0, top - visible.minY), expanded ? requestedHeight : 8)
        let frame = CGRect(x: bounded(screen.midX - width / 2, screen.minX, screen.maxX - width),
                           y: top - height, width: width, height: height)
        return .init(frame: frame, bodyFrame: frame, capFrame: nil, topInset: 0, cameraWidth: 0, cameraHeight: 0, hasNotch: false, anchored: true)
    }

    private static func cutoutGap(screen: CGRect, bandHeight: Double, left: CGRect?, right: CGRect?) -> CGRect? {
        guard let left, let right, usable(left), usable(right),
              left.maxY >= screen.maxY - bandHeight, right.maxY >= screen.maxY - bandHeight,
              left.maxX >= screen.minX, right.minX <= screen.maxX,
              right.minX > left.maxX else { return nil }
        let width = right.minX - left.maxX
        guard width <= screen.width else { return nil }
        let gap = CGRect(x: left.maxX, y: screen.maxY - bandHeight, width: width, height: bandHeight)
        guard gap.minX >= screen.minX, gap.maxX <= screen.maxX else { return nil }
        return gap
    }
    private static func usable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && [rect.minX, rect.minY, rect.maxX, rect.maxY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }
    private static func bounded(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), max(lower, upper))
    }
}
