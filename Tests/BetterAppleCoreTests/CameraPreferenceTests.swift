import XCTest
@testable import BetterAppleCore

final class CameraPreferenceTests: XCTestCase {
    func testOlderSettingsDefaultToCameraAndFloatingChoiceRoundTrips() throws {
        let store = SettingsStore()
        let older = try store.importSettings(Data(#"{"island":{"width":244,"offsetX":42}}"#.utf8))
        XCTAssertEqual(older.island.placementMode, .camera)
        XCTAssertEqual(older.island.width, 244)
        XCTAssertEqual(older.island.offsetX, 42)
        var floating = older
        floating.island.placementMode = .floating
        let restored = try store.importSettings(store.export(floating))
        XCTAssertEqual(restored.island.placementMode, .floating)
        XCTAssertEqual(restored.island.width, 244)
    }
    func testUnknownPlacementIsRejectedAndPresetsKeepPlacement() throws {
        XCTAssertThrowsError(try SettingsStore().importSettings(Data(#"{"island":{"placement":"unknown"}}"#.utf8)))
        var settings = AppSettings()
        settings.island.placementMode = .floating
        settings.applyPreset(.glass)
        XCTAssertEqual(settings.island.placementMode, .floating)
        settings.island.placementMode = .camera
        settings.applyPreset(.compact)
        XCTAssertEqual(settings.island.placementMode, .camera)
    }
}
