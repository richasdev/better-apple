import XCTest
@testable import BetterAppleCore

final class CalculatorTests: XCTestCase {
    func testPrecedenceAndScientificNotation() throws {
        XCTAssertEqual(try Calculator.evaluate("2 + 3 * (8 - 4) / 2"), 8)
        XCTAssertEqual(try Calculator.evaluate("2^3^2"), 512)
        XCTAssertEqual(try Calculator.evaluate("-2^2"), -4)
        XCTAssertEqual(try Calculator.evaluate("2^-2"), 0.25)
        XCTAssertEqual(try Calculator.evaluate("1e3 + .5"), 1000.5)
        XCTAssertEqual(try Calculator.evaluate("200 × 15%"), 30)
    }
    func testUnsafeAndInvalidInputsAreRejected() {
        for expression in ["", "1/0", "1 +", "foo()", "1; do shell script", "2(3)", "1e", "1.2.3", "2^1024", "(-1)^.5"] {
            XCTAssertThrowsError(try Calculator.evaluate(expression), expression)
        }
        XCTAssertThrowsError(try Calculator.evaluate(String(repeating: "(", count: 80) + "1" + String(repeating: ")", count: 80)))
        XCTAssertThrowsError(try Calculator.evaluate(String(repeating: "1", count: 1025)))
    }
}

final class CountdownTests: XCTestCase {
    let origin = Date(timeIntervalSince1970: 1_000)
    func testPauseResumeAndDelayedCompletion() {
        var timer = Countdown()
        timer.start(seconds: 60, now: origin)
        timer.pause(now: origin.addingTimeInterval(15))
        XCTAssertEqual(timer.remaining(at: origin.addingTimeInterval(1000)), 45)
        timer.resume(now: origin.addingTimeInterval(1000))
        XCTAssertEqual(timer.remaining(at: origin.addingTimeInterval(1010)), 35)
        XCTAssertTrue(timer.isFinished(at: origin.addingTimeInterval(2000)))
        XCTAssertEqual(timer.remaining(at: origin.addingTimeInterval(2000)), 0)
        timer.cancel()
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(timer.isFinished(at: origin))
    }
    func testInvalidAndExcessiveDuration() {
        var timer = Countdown()
        timer.start(seconds: .infinity, now: origin)
        XCTAssertFalse(timer.isRunning)
        timer.start(seconds: 999999999, now: origin)
        XCTAssertEqual(timer.remaining(at: origin), 604800)
    }
}

final class SettingsTests: XCTestCase {
    func testDefaultsAndRoundTrip() throws {
        let store = SettingsStore()
        var settings = AppSettings()
        settings.widgets = [WidgetConfiguration(kind: .notes)]
        settings.widgets[0].notes = "Persist a real note"
        XCTAssertEqual(try store.importSettings(store.export(settings)), settings)
        let partial = Data(#"{"island":{"width":260}}"#.utf8)
        let decoded = try store.importSettings(partial)
        XCTAssertEqual(decoded.island.width, 260)
        XCTAssertEqual(decoded.island.height, IslandSettings().height)
        let widgetPartial = try store.importSettings(Data(#"{"widgets":[{"kind":"notes","notes":"hello"}]}"#.utf8))
        XCTAssertEqual(widgetPartial.widgets.first?.notes, "hello")
        XCTAssertEqual(widgetPartial.widgets.first?.width, 280)
    }
    func testValidationRepairsLayoutAndModuleInvariants() throws {
        var settings = AppSettings()
        settings.island.width = -10
        settings.island.modules = [.timer, .timer]
        settings.island.defaultModule = .music
        settings.dock.applications = ["relative.app", "/Applications/Music.app"]
        let valid = try settings.validated()
        XCTAssertEqual(valid.island.width, 100)
        XCTAssertEqual(valid.island.modules, [.timer])
        XCTAssertEqual(valid.island.defaultModule, .timer)
        XCTAssertEqual(valid.dock.applications, ["/Applications/Music.app"])
        settings.island.width = .nan
        XCTAssertThrowsError(try settings.validated())
    }
    func testInvalidImportsDoNotReplaceSavedSettings() throws {
        let suite = "BetterAppleTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings()
        settings.island.width = 300
        try store.save(settings)
        XCTAssertThrowsError(try store.importSettings(Data(#"{"schemaVersion":99}"#.utf8)))
        XCTAssertEqual(store.load().island.width, 300)
        XCTAssertThrowsError(try store.importSettings(Data("[]".utf8)))
        XCTAssertThrowsError(try store.importSettings(Data(repeating: 65, count: 2 * 1024 * 1024 + 1)))
    }
}
