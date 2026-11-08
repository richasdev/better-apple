import XCTest
@testable import BetterAppleCore

final class CalculatorHistoryTests: XCTestCase {
    func testBoundedHistoryDeduplicatesConsecutiveAnswersAndRejectsInvalidExpressions() throws {
        var history = CalculatorHistory()
        for index in 0..<40 { try history.add("\(index) + 1") }
        XCTAssertEqual(history.entries.count, CalculatorHistory.limit)
        XCTAssertEqual(history.entries.first?.result, 40)
        let firstID = history.entries.first?.id
        try history.add(" 39 + 1 ")
        XCTAssertEqual(history.entries.count, CalculatorHistory.limit)
        XCTAssertEqual(history.entries.first?.id, firstID)
        XCTAssertThrowsError(try history.add("1 / 0"))
        XCTAssertEqual(history.entries.first?.id, firstID)
        XCTAssertThrowsError(try history.add("1", at: Date(timeIntervalSinceReferenceDate: .infinity)))
    }

    func testHistoryRoundTripRecomputesUntrustedAnswersAndSupportsDeletion() throws {
        let entry = CalculatorHistoryEntry(expression: "2 ^ 8", result: 999, date: Date(timeIntervalSince1970: 100))
        let unsafe = CalculatorHistoryEntry(expression: "FUNCTION(1)", result: 1)
        var history = CalculatorHistory(data: try JSONEncoder().encode([entry, unsafe, entry]))
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.result, 256)
        XCTAssertEqual(CalculatorHistory(data: try history.encoded()).entries, history.entries)
        history.remove(id: entry.id)
        XCTAssertTrue(history.entries.isEmpty)
        try history.add("50%")
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(CalculatorHistory(data: Data("{}".utf8)).entries.isEmpty)
        XCTAssertTrue(CalculatorHistory(data: Data(repeating: 32, count: 128 * 1024 + 1)).entries.isEmpty)
    }
}
