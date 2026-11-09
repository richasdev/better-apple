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
    func testPhysicalNotchCollapsedSilhouetteAttachesToTopWithShoulders() {
        let layout = CameraIslandGeometry.layout(screen: notched, expanded: false, expandedWidth: 420, expandedHeight: 320)
        XCTAssertTrue(layout.hasNotch)
        XCTAssertEqual(layout.cameraWidth, 160)
        XCTAssertEqual(layout.cameraHeight, 37)
        XCTAssertEqual(layout.topInset, 37)
        XCTAssertEqual(layout.bodyFrame, CGRect(x: 676, y: 941, width: 160, height: 4))
        XCTAssertEqual(layout.capFrame, CGRect(x: 664, y: 941, width: 184, height: 41))
        XCTAssertEqual(layout.frame, CGRect(x: 664, y: 941, width: 184, height: 41))
        assertContinuous(layout)
    }
    func testExpansionWidensCapWithBodyAndKeepsTopAnchorFixed() {
        let closed = CameraIslandGeometry.layout(screen: notched, expanded: false, expandedWidth: 420, expandedHeight: 320)
        let opened = CameraIslandGeometry.layout(screen: notched, expanded: true, expandedWidth: 420, expandedHeight: 320)
        XCTAssertEqual(opened.bodyFrame, CGRect(x: 546, y: 625, width: 420, height: 320))
        XCTAssertEqual(opened.capFrame, CGRect(x: 534, y: 941, width: 444, height: 41))
        XCTAssertEqual(opened.frame, CGRect(x: 534, y: 625, width: 444, height: 357))
        XCTAssertEqual(opened.capFrame?.maxY, closed.capFrame?.maxY)
        XCTAssertEqual(opened.capFrame?.height, closed.capFrame?.height)
        XCTAssertGreaterThan(opened.capFrame!.width, closed.capFrame!.width)
        assertContinuous(opened)
        let narrow = CameraIslandGeometry.layout(screen: notched, expanded: true, expandedWidth: 100, expandedHeight: 200)
        XCTAssertEqual(narrow.bodyFrame.width, 192)
        XCTAssertEqual(narrow.capFrame?.width, 216)
    }
    func testRegularDisplayGetsSyntheticTopAttachedNotchInsteadOfPill() {
        let metrics = CameraScreenMetrics(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 48, width: 1512, height: 910))
        let closed = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 420, expandedHeight: 320)
        let opened = CameraIslandGeometry.layout(screen: metrics, expanded: true, expandedWidth: 420, expandedHeight: 320)
        XCTAssertFalse(closed.hasNotch)
        XCTAssertEqual(closed.cameraWidth, 185)
        XCTAssertEqual(closed.cameraHeight, 24)
        XCTAssertEqual(closed.topInset, 24)
        XCTAssertEqual(closed.bodyFrame, CGRect(x: 663.5, y: 958, width: 185, height: 0))
        XCTAssertEqual(closed.capFrame, CGRect(x: 651.5, y: 958, width: 209, height: 24))
        XCTAssertEqual(opened.bodyFrame, CGRect(x: 546, y: 638, width: 420, height: 320))
        XCTAssertEqual(opened.capFrame, CGRect(x: 534, y: 954, width: 444, height: 28))
        XCTAssertEqual(closed.frame.maxY, screen.maxY)
        XCTAssertEqual(opened.frame.maxY, screen.maxY)
        assertContinuous(closed); assertContinuous(opened)
    }
    func testAutomaticMenuBarHidingDoesNotDetachSyntheticNotch() {
        let metrics = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen)
        for expanded in [false, true] {
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: expanded, expandedWidth: 420, expandedHeight: 320)
            XCTAssertEqual(layout.topInset, 24)
            XCTAssertEqual(layout.capFrame?.maxY, screen.maxY)
            XCTAssertEqual(layout.bodyFrame.maxY, screen.maxY - 24)
        }
    }
    func testMenuBandTallerThanPhysicalOrSyntheticCameraIsReserved() {
        let metrics = CameraScreenMetrics(screenFrame: screen,
            visibleFrame: CGRect(x: 0, y: 87, width: 1512, height: 862), safeAreaTop: 32,
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))
        for expanded in [false, true] {
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: expanded, expandedWidth: 440, expandedHeight: 340)
            XCTAssertEqual(layout.topInset, 33)
            XCTAssertEqual(layout.bodyFrame.maxY, 949)
            XCTAssertEqual(layout.capFrame?.maxY, 982)
            XCTAssertEqual(layout.capFrame?.minY, 945)
            XCTAssertEqual(layout.bodyFrame.height, expanded ? 340 : 4)
            assertContinuous(layout)
        }
        let tallMenu = CameraScreenMetrics(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 932))
        let synthetic = CameraIslandGeometry.layout(screen: tallMenu, expanded: false, expandedWidth: 420, expandedHeight: 320)
        XCTAssertFalse(synthetic.hasNotch)
        XCTAssertEqual(synthetic.cameraHeight, 50)
        XCTAssertEqual(synthetic.topInset, 50)
        XCTAssertEqual(synthetic.capFrame?.maxY, screen.maxY)
        XCTAssertEqual(synthetic.bodyFrame.maxY, 932)
    }
    func testSyntheticCompactNeverExceedsVisibleMenuBarHeight() {
        for height in [22.0, 24, 33, 40] {
            let metrics = CameraScreenMetrics(screenFrame: screen,
                visibleFrame: CGRect(x: 0, y: 0, width: screen.width, height: screen.height - height))
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 440, expandedHeight: 340)
            XCTAssertEqual(layout.capFrame?.height, CGFloat(height))
            XCTAssertEqual(layout.capFrame?.minY, metrics.visibleFrame.maxY)
            XCTAssertEqual(layout.bodyFrame.height, 0)
        }
        let hiddenBar = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen, menuBarHeight: 28)
        XCTAssertEqual(CameraIslandGeometry.layout(screen: hiddenBar, expanded: false, expandedWidth: 440, expandedHeight: 340).capFrame?.height, 28)
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
        XCTAssertEqual(layout.bodyFrame.maxY, 645)
        assertContinuous(layout)
    }
    func testMissingOrMalformedAuxiliaryAreasUseSame185PointFallback() {
        let noAuxiliary = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen, safeAreaTop: 37)
        let regular = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen)
        let invalidAuxiliary = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen, safeAreaTop: 37,
            auxiliaryLeft: CGRect(x: -9999, y: 0, width: 10, height: 1), auxiliaryRight: CGRect(x: 9999, y: 0, width: 10, height: 1))
        for metrics in [noAuxiliary, regular, invalidAuxiliary] {
            let layout = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 420, expandedHeight: 320)
            XCTAssertEqual(layout.cameraWidth, 185)
            XCTAssertEqual(layout.bodyFrame.width, 185)
            XCTAssertEqual(layout.capFrame?.width, 209)
            XCTAssertEqual(layout.frame.midX, screen.midX)
            XCTAssertEqual(layout.capFrame?.maxY, screen.maxY)
            assertContinuous(layout)
        }
        let measured185 = CameraScreenMetrics(screenFrame: screen, visibleFrame: screen, safeAreaTop: 32,
            auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))
        let real = CameraIslandGeometry.layout(screen: measured185, expanded: false, expandedWidth: 420, expandedHeight: 320)
        let synthetic = CameraIslandGeometry.layout(screen: regular, expanded: false, expandedWidth: 420, expandedHeight: 320)
        XCTAssertTrue(real.hasNotch)
        XCTAssertFalse(synthetic.hasNotch)
        XCTAssertEqual(real.cameraWidth, 185)
        XCTAssertEqual(real.bodyFrame.width, synthetic.bodyFrame.width)
        XCTAssertEqual(real.capFrame?.width, synthetic.capFrame?.width)
        XCTAssertEqual(synthetic.capFrame?.height, 24)
        XCTAssertEqual(synthetic.bodyFrame.height, 0)
    }
    func testTinyScreensAndLargePreferencesKeepAllWindowsWithinPhysicalBounds() {
        for physical in [false, true] {
            for small in [CGRect(x: -120, y: 40, width: 120, height: 100), CGRect(x: -14, y: -8, width: 14, height: 8)] {
                let metrics = CameraScreenMetrics(screenFrame: small, visibleFrame: small, safeAreaTop: physical ? 20 : 0)
                for expanded in [false, true] {
                    let layout = CameraIslandGeometry.layout(screen: metrics, expanded: expanded, expandedWidth: 99999, expandedHeight: 99999)
                    assertBounds(layout.frame, in: small)
                    assertBounds(layout.bodyFrame, in: small)
                    assertBounds(layout.capFrame!, in: small)
                    XCTAssertEqual(layout.frame.maxY, small.maxY)
                    XCTAssertLessThanOrEqual(layout.topInset, small.height)
                    XCTAssertEqual(layout.bodyFrame.width, min(layout.cameraWidth, small.width - min(24, max(0, small.width - 1))))
                }
            }
        }
    }
    func testInvalidMeasurementsCannotCreateNonFiniteFrames() {
        let metrics = CameraScreenMetrics(screenFrame: screen, visibleFrame: .null, safeAreaTop: .nan)
        let layout = CameraIslandGeometry.layout(screen: metrics, expanded: true, expandedWidth: .infinity, expandedHeight: .nan)
        XCTAssertFalse(layout.hasNotch)
        XCTAssertTrue(screen.contains(layout.frame))
        XCTAssertEqual(layout.bodyFrame.width, 420)
        XCTAssertEqual(layout.frame.width, 444)
        let missing = CameraScreenMetrics(screenFrame: .zero, visibleFrame: .zero)
        let empty = CameraIslandGeometry.layout(screen: missing, expanded: true, expandedWidth: 420, expandedHeight: 320)
        XCTAssertEqual(empty.frame, .zero)
        XCTAssertNil(empty.capFrame)
        let overflow = CGRect(x: Double.greatestFiniteMagnitude, y: 0, width: Double.greatestFiniteMagnitude, height: 100)
        XCTAssertEqual(CameraIslandGeometry.layout(screen: .init(screenFrame: overflow, visibleFrame: overflow), expanded: true, expandedWidth: 420, expandedHeight: 320).frame, .zero)
    }
    private func assertContinuous(_ layout: IslandWindowLayout, file: StaticString = #filePath, line: UInt = #line) {
        guard let cap = layout.capFrame else { XCTFail("Valid screen requires an attached cap", file: file, line: line); return }
        XCTAssertEqual(cap.width, layout.bodyFrame.width + 24, file: file, line: line)
        XCTAssertEqual(layout.bodyFrame.minX, cap.minX + 12, file: file, line: line)
        XCTAssertEqual(cap.maxX - layout.bodyFrame.maxX, 12, file: file, line: line)
        XCTAssertEqual(layout.bodyFrame.maxY - cap.minY, layout.bodyFrame.height == 0 ? 0 : 4, file: file, line: line)
        XCTAssertEqual(layout.frame.maxY, cap.maxY, file: file, line: line)
        XCTAssertEqual(layout.frame.minY, layout.bodyFrame.minY, file: file, line: line)
    }
    func testMusicWingsReserveCameraAndNeverIncreaseCollapsedMenuBand() {
        for safeTop in [0.0, 32.0] {
            let screen = CGRect(x: -1200, y: 50, width: 1200, height: 800)
            let metrics = CameraScreenMetrics(screenFrame: screen, visibleFrame: CGRect(x: -1200, y: 50, width: 1200, height: 770), safeAreaTop: safeTop, menuBarHeight: 30)
            let idle = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 560, expandedHeight: 140)
            let music = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 560, expandedHeight: 140, compactExtension: 88)
            XCTAssertEqual(music.cameraWidth, idle.cameraWidth)
            XCTAssertEqual(music.capFrame?.height, idle.capFrame?.height)
            XCTAssertEqual(music.capFrame!.midX, idle.capFrame!.midX)
            XCTAssertEqual(music.capFrame!.width - idle.capFrame!.width, 88)
            XCTAssertEqual(music.bodyFrame.height, idle.bodyFrame.height)
            assertBounds(music.frame, in: screen)
            let invalid = CameraIslandGeometry.layout(screen: metrics, expanded: false, expandedWidth: 560, expandedHeight: 140, compactExtension: .nan)
            XCTAssertEqual(invalid, idle)
        }
    }
    private func assertBounds(_ rect: CGRect, in screen: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(rect.minX, screen.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, screen.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, screen.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, screen.maxY, file: file, line: line)
    }
}
