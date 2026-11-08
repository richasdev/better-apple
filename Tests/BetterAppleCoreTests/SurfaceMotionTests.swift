import XCTest
@testable import BetterAppleCore

final class SurfaceMotionTests: XCTestCase {
    func testDisabledMotionHasNoDelayedContentOrGeometry() {
        for duration in [0, 0.24, 0.8] {
            let plan = SurfaceMotionPlan.island(expanded: true, requestedDuration: duration, reduceMotion: true)
            XCTAssertEqual(plan.windowDuration, 0)
            XCTAssertEqual(plan.contentDuration, 0)
            XCTAssertEqual(plan.revealDelay, 0)
        }
        XCTAssertEqual(SurfaceMotionPlan.island(expanded: false, requestedDuration: 0, reduceMotion: false).windowDuration, 0)
    }
    func testChoreographyFinishesWithinWindowAndDismissesFaster() {
        for requested in [0.01, 0.12, 0.24, 0.8] {
            let entrance = SurfaceMotionPlan.island(expanded: true, requestedDuration: requested, reduceMotion: false)
            let exit = SurfaceMotionPlan.island(expanded: false, requestedDuration: requested, reduceMotion: false)
            XCTAssertLessThanOrEqual(entrance.revealDelay + entrance.contentDuration, entrance.windowDuration + 0.000001)
            XCTAssertLessThanOrEqual(exit.revealDelay + exit.contentDuration, exit.windowDuration + 0.000001)
            XCTAssertLessThan(exit.windowDuration, entrance.windowDuration)
        }
    }
    func testMalformedPreferencesCannotScheduleUnboundedOrInvalidAnimations() {
        for duration in [-1, 999, Double.nan, .infinity] {
            let plan = SurfaceMotionPlan.island(expanded: true, requestedDuration: duration, reduceMotion: false)
            XCTAssertTrue(plan.windowDuration.isFinite)
            XCTAssertTrue((0...0.8).contains(plan.windowDuration))
            XCTAssertTrue(plan.revealDelay.isFinite)
        }
    }
}
