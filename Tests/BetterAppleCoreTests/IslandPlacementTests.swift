import XCTest
import CoreGraphics
@testable import BetterAppleCore

final class IslandPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private var notched: CameraScreenMetrics {
        .init(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 48, width: 1512, height: 897), safeAreaTop: 37,
              auxiliaryLeft: CGRect(x: 0, y: 945, width: 676, height: 37),
              auxiliaryRight: CGRect(x: 836, y: 945, width: 676, height: 37))
    }
    func testCollapsedCutoutIsFlushAndOnlyExposesThinHoverRim() {
        let layout = CameraIslandGeometry.layout(screen: notched, expanded: false, expandedWidth: 420, expandedHeight: 320)
        XCTAssertTrue(layout.hasNotch)
        XCTAssertEqual(layout.cameraWidth, 160)
        XCTAssertEqual(layout.cameraHeight, 37)
        XCTAssertEqual(layout.frame, CGRect(x: 672, y: 941, width: 168, height: 41))
        XCTAssertEqual(layout.frame.maxY, screen.maxY)
        XCTAssertEqual(layout.frame.midX, screen.midX)
        XCTAssertEqual(layout.frame.height - layout.cameraHeight, 4)
        XCTAssertEqual(layout.topInset, 0)
        XCTAssertEqual(layout.bodyFrame, CGRect(x: 672, y: 941, width: 168, height: 4))
        XCTAssertEqual(layout.capFrame, CGRect(x: 676, y: 941, width: 160, height: 41))
    }
    func testExpansionKeepsCameraAnchorAndControlsBelowSensor() {
        let layout = CameraIslandGeometry.layout(screen: notched, expanded: true, expandedWidth: 420, expandedHeight: 320)
        XCTAssertEqual(layout.frame.maxY, screen.maxY)
        XCTAssertEqual(layout.frame.midX, screen.midX)
        XCTAssertEqual(layout.frame.size, CGSize(width: 420, height: 357))
        XCTAssertEqual(layout.topInset, 37)
        XCTAssertEqual(layout.frame.maxY - layout.topInset, 945)
        XCTAssertEqual(layout.frame.height - layout.topInset, 320)
        XCTAssertEqual(layout.bodyFrame, CGRect(x: 546, y: 625, width: 420, height: 320))
        XCTAssertEqual(layout.bodyFrame.maxY, screen.maxY - layout.cameraHeight)
        XCTAssertEqual(layout.capFrame, CGRect(x: 676, y: 941, width: 160, height: 41))
        XCTAssertLessThan(layout.capFrame!.width, layout.bodyFrame.width)
        let narrow = CameraIslandGeometry.layout(screen: notched, expanded: true, expandedWidth: 100, expandedHeight: 200)
        XCTAssertEqual(narrow.frame.width, 192)
    }
    func testNoNotchUsesSubtlePillBelowMenuWithStableExpansionAnchor() {
        let metrics = CameraScreenMetrics(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 48, width: 1512, height: 910))
        let closed = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 420, expandedHeight: 320)
        let opened = CameraIslandGeometry.layout(screen: metrics, expanded: true, expandedWidth: 420, expandedHeight: 320)
        XCTAssertFalse(closed.hasNotch)
        XCTAssertEqual(closed.frame.size, CGSize(width: 80, height: 8))
        XCTAssertEqual(closed.frame.maxY, 956)
        XCTAssertEqual(opened.frame.maxY, closed.frame.maxY)
        XCTAssertEqual(closed.frame.midX, screen.midX)
        XCTAssertEqual(opened.topInset, 0)
        XCTAssertEqual(opened.bodyFrame, opened.frame)
        XCTAssertNil(opened.capFrame)
    }
    func testBodyHonorsMenuBandTallerThanCameraSafeArea() {
        let metrics = CameraScreenMetrics(screenFrame: screen,
            visibleFrame: CGRect(x: 0, y: 87, width: 1512, height: 862), safeAreaTop: 32,
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))
        for expanded in [false, true] {
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: expanded, expandedWidth: 440, expandedHeight: 340)
            XCTAssertEqual(layout.bodyFrame.maxY, 949)
            XCTAssertEqual(layout.capFrame?.maxY, 982)
            XCTAssertEqual(layout.capFrame?.minY, 945)
            XCTAssertEqual(layout.bodyFrame.height, expanded ? 340 : 4)
        }
    }
    func testGlobalNegativeDisplayCoordinatesStayCorrect() {
        let metrics = CameraScreenMetrics(screenFrame: CGRect(x: -1512, y: -300, width: 1512, height: 982),
            visibleFrame: CGRect(x: -1512, y: -252, width: 1512, height: 897), safeAreaTop: 37,
            auxiliaryLeft: CGRect(x: -1512, y: 645, width: 676, height: 37),
            auxiliaryRight: CGRect(x: -676, y: 645, width: 676, height: 37))
        let layout = CameraIslandGeometry.layout(screen: metrics, expanded: true, expandedWidth: 440, expandedHeight: 340)
        XCTAssertEqual(layout.frame.midX, -756)
        XCTAssertEqual(layout.frame.maxY, 682)
        XCTAssertTrue(metrics.screenFrame.contains(layout.frame))
        XCTAssertLessThanOrEqual(layout.bodyFrame.maxY, metrics.screenFrame.maxY - layout.cameraHeight)
    }
    func testUnavailableOrMalformedAuxiliaryAreasUseBoundedFallback() {
        let noAuxiliary = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen, safeAreaTop: 37)
        let invalidAuxiliary = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen, safeAreaTop: 37,
            auxiliaryLeft: CGRect(x: -9999, y: 0, width: 10, height: 1), auxiliaryRight: CGRect(x: 9999, y: 0, width: 10, height: 1))
        for metrics in [noAuxiliary, invalidAuxiliary] {
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 420, expandedHeight: 320)
            XCTAssertEqual(layout.cameraWidth, 180)
            XCTAssertEqual(layout.frame.width, 188)
            XCTAssertEqual(layout.frame.midX, screen.midX)
            XCTAssertNil(layout.capFrame)
        }
    }
    func testTinyScreensAndLargePreferencesNeverLeavePhysicalBounds() {
        let small = CGRect(x: -120, y: 40, width: 120, height: 100)
        let metrics = CameraScreenMetrics(screenFrame: small, visibleFrame: small, safeAreaTop: 20,
            auxiliaryLeft: CGRect(x: -120, y: 120, width: 52, height: 20),
            auxiliaryRight: CGRect(x: -52, y: 120, width: 52, height: 20))
        for expanded in [false, true] {
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: expanded, expandedWidth: 99999, expandedHeight: 99999)
            XCTAssertTrue(small.contains(layout.frame))
            XCTAssertLessThanOrEqual(layout.topInset, layout.frame.height)
            XCTAssertEqual(layout.frame.maxY, small.maxY)
            XCTAssertLessThanOrEqual(layout.bodyFrame.maxY, small.maxY - layout.cameraHeight)
            XCTAssertTrue(small.contains(layout.bodyFrame))
            XCTAssertTrue(small.contains(layout.capFrame!))
        }
    }
    func testInvalidMeasurementsNeverProduceNaNOrInfiniteWindowFrames() {
        let metrics = CameraScreenMetrics(screenFrame: screen, visibleFrame: .null, safeAreaTop: .nan)
        let layout = CameraIslandGeometry.layout(screen: metrics, expanded: true, expandedWidth: .infinity, expandedHeight: .nan)
        XCTAssertFalse(layout.hasNotch)
        XCTAssertTrue(screen.contains(layout.frame))
        XCTAssertEqual(layout.frame.width, 420)
        let missing = CameraScreenMetrics(screenFrame: .zero, visibleFrame: .zero)
        XCTAssertEqual(CameraIslandGeometry.layout(screen: missing, expanded: true, expandedWidth: 420, expandedHeight: 320).frame, .zero)
        let overflow = CGRect(x: Double.greatestFiniteMagnitude, y: 0, width: Double.greatestFiniteMagnitude, height: 100)
        XCTAssertEqual(CameraIslandGeometry.layout(screen: .init(screenFrame: overflow, visibleFrame: overflow), expanded: true, expandedWidth: 420, expandedHeight: 320).frame, .zero)
    }
}
