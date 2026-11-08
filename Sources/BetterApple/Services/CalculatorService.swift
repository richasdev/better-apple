import AppKit
import Combine
import BetterAppleCore

@MainActor
final class CalculatorService: ObservableObject {
    @Published var expression = "" { didSet { evaluate() } }
    @Published var historyEnabled: Bool {
        didSet {
            defaults.set(historyEnabled, forKey: "calculator.historyEnabled")
            if !historyEnabled { clearHistory() }
        }
    }
    @Published private(set) var history: [CalculatorHistoryEntry] = []
    @Published private(set) var resultText = "0"
    @Published private(set) var errorMessage: String?
    @Published private(set) var copied = false
    private let defaults: UserDefaults
    private var record: CalculatorHistory
    private var result: Double?
    private static let historyKey = "calculator.history"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: "calculator.historyEnabled")
        historyEnabled = enabled
        record = CalculatorHistory(data: enabled ? defaults.data(forKey: Self.historyKey) : nil)
        history = record.entries
    }

    func evaluate() {
        copied = false
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = nil; resultText = "0"; errorMessage = nil; return
        }
        do {
            let value = try Calculator.evaluate(expression)
            result = value; resultText = Calculator.formatted(value); errorMessage = nil
        } catch {
            result = nil; resultText = "—"; errorMessage = error.localizedDescription
        }
    }

    func commit() {
        evaluate()
        guard result != nil, historyEnabled else { return }
        do { try record.add(expression); persistHistory() }
        catch { errorMessage = error.localizedDescription }
    }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        // An invariant decimal point keeps copied answers reusable by the parser,
        // even when the system's locale formats a decimal with a comma.
        let success = NSPasteboard.general.setString(Calculator.formatted(result), forType: .string)
        commit()
        copied = success
    }

    func use(_ entry: CalculatorHistoryEntry) { expression = entry.expression }
    func removeHistory(id: UUID) { record.remove(id: id); persistHistory() }
    func clearHistory() {
        record.clear(); history = []
        defaults.removeObject(forKey: Self.historyKey)
    }
    private func persistHistory() {
        history = record.entries
        guard historyEnabled else { return }
        do { defaults.set(try record.encoded(), forKey: Self.historyKey) }
        catch { errorMessage = error.localizedDescription }
    }
}
