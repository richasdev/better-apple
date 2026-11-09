import XCTest
@testable import BetterAppleCore

final class AppearanceTests: XCTestCase {
    func testLegacySettingsAndPartialAppearanceRemainCompatible() throws {
        let legacy = try JSONEncoder().encode(AppSettings())
        XCTAssertNil(try JSONDecoder().decode(AppSettings.self, from: legacy).island.appearance)
        let store = SettingsStore()
        let custom = try store.importSettings(Data(#"{"island":{"appearance":{"theme":"light","accent":"orange","opacity":0.7}}}"#.utf8))
        XCTAssertEqual(custom.island.visual.theme, .light)
        XCTAssertEqual(custom.island.visual.accent, .orange)
        XCTAssertEqual(custom.island.visual.opacity, 0.7)
        XCTAssertEqual(custom.island.visual.cornerRadius, 26)
        XCTAssertEqual(try store.importSettings(store.export(custom)), custom)
    }
    func testAppearanceValidatesUntrustedNumbers() throws {
        var appearance = IslandAppearance()
        appearance.cornerRadius = -100; appearance.opacity = 9; appearance.animationDuration = 9
        let valid = try appearance.validated()
        XCTAssertEqual(valid.cornerRadius, 0)
        XCTAssertEqual(valid.opacity, 1)
        XCTAssertEqual(valid.animationDuration, 0.8)
        appearance.animationDuration = .infinity
        XCTAssertThrowsError(try appearance.validated())
    }
    func testPresetsResetVisualsWithoutDiscardingModulesOrPosition() {
        var settings = AppSettings()
        settings.island.modules = [.timer, .calculator]
        settings.island.defaultModule = .timer
        settings.island.offsetX = 84
        settings.applyPreset(.minimal)
        XCTAssertTrue(settings.island.minimal)
        settings.applyPreset(.glass)
        XCTAssertEqual(settings.island.visual.material, .glass)
        settings.applyPreset(.default)
        XCTAssertFalse(settings.island.minimal)
        XCTAssertEqual(settings.dock.iconSize, 48)
        XCTAssertEqual(settings.island.visual, IslandAppearance())
        XCTAssertEqual(settings.island.modules, [.timer, .calculator])
        XCTAssertEqual(settings.island.defaultModule, .timer)
        XCTAssertEqual(settings.island.offsetX, 84)
        let defaultSize = settings.island
        for preset in [AppearancePreset.minimal, .compact] {
            settings.applyPreset(preset)
            XCTAssertLessThan(settings.island.expandedWidth, defaultSize.expandedWidth)
            XCTAssertLessThan(settings.island.expandedHeight, defaultSize.expandedHeight)
        }
    }
}
