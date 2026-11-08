import Foundation

public struct CalculatorHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let expression: String
    public let result: Double
    public let date: Date

    public init(id: UUID = UUID(), expression: String, result: Double, date: Date = Date()) {
        self.id = id; self.expression = expression; self.result = result; self.date = date
    }
}

/// A small local history. Loaded results are recomputed with the safe parser,
/// rather than trusting a result supplied by a modified preferences file.
public struct CalculatorHistory: Sendable {
    public static let limit = 30
    public private(set) var entries: [CalculatorHistoryEntry] = []
    public init() {}
    public init(data: Data?) {
        guard let data, data.count <= 128 * 1024,
              let decoded = try? JSONDecoder().decode([CalculatorHistoryEntry].self, from: data) else { return }
        var identifiers = Set<UUID>()
        entries = decoded.prefix(Self.limit).compactMap { entry in
            guard entry.date.timeIntervalSinceReferenceDate.isFinite,
                  identifiers.insert(entry.id).inserted,
                  let value = try? Calculator.evaluate(entry.expression) else { return nil }
            return CalculatorHistoryEntry(id: entry.id, expression: entry.expression, result: value, date: entry.date)
        }
    }
    @discardableResult
    public mutating func add(_ expression: String, at date: Date = Date()) throws -> CalculatorHistoryEntry {
        let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try Calculator.evaluate(expression)
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw CalculatorError.nonFinite }
        if let first = entries.first, first.expression == expression, first.result == result { return first }
        let entry = CalculatorHistoryEntry(expression: expression, result: result, date: date)
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        return entry
    }
    public mutating func remove(id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func clear() { entries.removeAll() }
    public func encoded() throws -> Data { try JSONEncoder().encode(entries) }
}
