import Foundation
import CoreGraphics

/// Public NSScreen measurements expressed in the same global coordinate space.
public struct CameraScreenMetrics: Equatable, Sendable {
    public let screenFrame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaTop: Double
    public let auxiliaryLeft: CGRect?
    public let auxiliaryRight: CGRect?
    public let menuBarHeight: Double

    public init(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: Double = 0,
                auxiliaryLeft: CGRect? = nil, auxiliaryRight: CGRect? = nil, menuBarHeight: Double = 24) {
        self.screenFrame = screenFrame; self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop; self.auxiliaryLeft = auxiliaryLeft; self.auxiliaryRight = auxiliaryRight
        self.menuBarHeight = menuBarHeight
    }
}

public struct IslandWindowLayout: Equatable, Sendable {
    public let frame: CGRect
    /// Interactive body below the reserved camera/menu band on every display.
    public let bodyFrame: CGRect
    /// Top-attached cap with shoulders; present on every valid display, including synthetic notches.
    public let capFrame: CGRect?
    /// Reserved top band of the complete silhouette in either state. Body-window content adds no extra inset.
    public let topInset: Double
    public let cameraWidth: Double
    public let cameraHeight: Double
    public let hasNotch: Bool
    public let anchored: Bool
}

public enum CameraIslandGeometry {
    public static func layout(screen metrics: CameraScreenMetrics, expanded: Bool,
                              expandedWidth: Double, expandedHeight: Double, compactExtension: Double = 0) -> IslandWindowLayout {
        let screen = metrics.screenFrame
        guard usable(screen) else {
            return .init(frame: .zero, bodyFrame: .zero, capFrame: nil, topInset: 0, cameraWidth: 0, cameraHeight: 0, hasNotch: false, anchored: true)
        }
        let safeTop = metrics.safeAreaTop.isFinite ? max(0, min(metrics.safeAreaTop, screen.height)) : 0
        let hasNotch = safeTop > 0
        let intersection = usable(metrics.visibleFrame) ? metrics.visibleFrame.intersection(screen) : .null
        let reservedMenuHeight = usable(intersection) ? max(0, screen.maxY - intersection.maxY) : 0
        let fallbackMenuHeight = metrics.menuBarHeight.isFinite ? max(1, metrics.menuBarHeight) : 24
        let syntheticHeight = min(screen.height, reservedMenuHeight > 0 ? reservedMenuHeight : fallbackMenuHeight)
        let cameraHeight = hasNotch ? safeTop : syntheticHeight
        let band = min(screen.height, max(cameraHeight, reservedMenuHeight))
        let cameraGap = hasNotch ? cutoutGap(screen: screen, bandHeight: safeTop,
                                             left: metrics.auxiliaryLeft, right: metrics.auxiliaryRight) : nil
        // The same top-attached silhouette is used on every display. Auxiliary
        // areas refine physical camera measurements; otherwise 185 pt is a visual
        // synthetic notch, not a claim that hardware was discovered.
        let shoulder = min(12, max(0, (screen.width - 1) / 2))
        let maximumBodyWidth = max(0, screen.width - shoulder * 2)
        let cameraWidth = min(maximumBodyWidth, cameraGap?.width ?? 185)
        let requestedWidth = expandedWidth.isFinite ? max(1, expandedWidth) : 420
        let wings = compactExtension.isFinite ? min(160, max(0, compactExtension)) : 0
        let bodyWidth = min(maximumBodyWidth, expanded ? max(requestedWidth, cameraWidth + 32) : cameraWidth + wings)
        let capWidth = min(screen.width, bodyWidth + shoulder * 2)
        let center = cameraGap?.midX ?? screen.midX
        let capX = bounded(center - capWidth / 2, screen.minX, screen.maxX - capWidth)
        let requestedHeight = expandedHeight.isFinite ? max(4, expandedHeight) : 320
        let bodyHeight = min(max(0, screen.height - band), expanded ? requestedHeight : (hasNotch ? 4 : 0))
        let body = CGRect(x: capX + shoulder, y: screen.maxY - band - bodyHeight,
                          width: bodyWidth, height: bodyHeight)
        // Four points overlap the body so rounding never creates a gap between
        // the cap and the lower body while their independent windows animate.
        let capHeight = min(screen.height, band + (expanded || hasNotch ? 4 : 0))
        let cap = CGRect(x: capX, y: screen.maxY - capHeight, width: capWidth, height: capHeight)
        let bottom = min(body.minY, cap.minY)
        let frame = CGRect(x: cap.minX, y: bottom, width: cap.width, height: screen.maxY - bottom)
        return .init(frame: frame, bodyFrame: body, capFrame: cap, topInset: band,
                     cameraWidth: cameraWidth, cameraHeight: cameraHeight, hasNotch: hasNotch, anchored: true)
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
