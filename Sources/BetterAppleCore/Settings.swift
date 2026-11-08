import Foundation

public enum ModuleID: String, Codable, CaseIterable, Identifiable, Sendable {
    case music, calendar, calculator, timer, system
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .calculator: return "plus.forwardslash.minus"
        case .timer: return "timer"
        case .system: return "chart.bar.xaxis"
        }
    }
}

public enum AppearancePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case `default`, minimal, glass, compact, custom
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct IslandSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var width = 220.0
    public var height = 34.0
    public var expandedWidth = 420.0
    public var expandedHeight = 250.0
    public var offsetX = 0.0
    public var offsetY = 6.0
    public var hoverToExpand = true
    public var autoCloseDelay = 1.5
    public var showInFullScreen = false
    public var allDisplays = false
    public var minimal = false
    public var modules = ModuleID.allCases
    public var defaultModule: ModuleID = .calculator
    public init() {}
}

public enum DockPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottom, left, right
    public var id: String { rawValue }
}

public struct DockSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var position: DockPosition = .bottom
    public var iconSize = 48.0
    public var spacing = 10.0
    public var opacity = 0.85
    public var autoHide = false
    public var allDisplays = false
    public var applications: [String] = []
    public init() {}
}

public enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case clock, analogClock, calendar, events, calculator, music, battery, system, notes, timer
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .analogClock: return "Analog Clock"
        case .events: return "Upcoming Events"
        default: return rawValue.capitalized
        }
    }
}

public enum WidgetTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
}

public struct WidgetConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: WidgetKind
    public var enabled = true
    public var x = 100.0
    public var y = 100.0
    public var width = 280.0
    public var height = 200.0
    public var opacity = 0.9
    public var theme: WidgetTheme = .system
    public var notes = ""
    public init(kind: WidgetKind) { self.kind = kind }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var island = IslandSettings()
    public var dock = DockSettings()
    public var widgets: [WidgetConfiguration] = []
    public var appearance: AppearancePreset = .default
    public var launchAtLogin = false
    public init() {}

    public mutating func applyPreset(_ preset: AppearancePreset) {
        appearance = preset
        switch preset {
        case .default: island.width = 220; island.height = 34; island.minimal = false; dock.opacity = 0.85
        case .minimal: island.width = 160; island.height = 28; island.minimal = true; dock.iconSize = 36
        case .glass: island.minimal = false; dock.opacity = 0.65
        case .compact: island.width = 190; island.height = 30; island.minimal = false; dock.iconSize = 36; dock.spacing = 6
        case .custom: break
        }
    }

    /// Bounds imported values before they reach window APIs, preventing invisible or oversized panels.
    public func validated() throws -> AppSettings {
        guard schemaVersion == 1 else { throw SettingsError.unsupportedVersion(schemaVersion) }
        var result = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>) throws -> Double {
            guard value.isFinite else { throw SettingsError.invalidNumber }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        result.island.width = try clamp(island.width, 100...600)
        result.island.height = try clamp(island.height, 24...80)
        result.island.expandedWidth = try clamp(island.expandedWidth, 300...800)
        result.island.expandedHeight = try clamp(island.expandedHeight, 180...650)
        result.island.offsetX = try clamp(island.offsetX, -10000...10000)
        result.island.offsetY = try clamp(island.offsetY, 0...500)
        result.island.autoCloseDelay = try clamp(island.autoCloseDelay, 0...60)
        var seen = Set<ModuleID>()
        result.island.modules = island.modules.filter { seen.insert($0).inserted }
        if result.island.modules.isEmpty { result.island.modules = [.calculator] }
        if !result.island.modules.contains(island.defaultModule) { result.island.defaultModule = result.island.modules[0] }
        result.dock.iconSize = try clamp(dock.iconSize, 24...96)
        result.dock.spacing = try clamp(dock.spacing, 0...32)
        result.dock.opacity = try clamp(dock.opacity, 0.1...1)
        result.dock.applications = Array(dock.applications.filter { $0.hasPrefix("/") && $0.hasSuffix(".app") }.prefix(100))
        guard widgets.count <= 50 else { throw SettingsError.tooManyWidgets }
        var widgetIDs = Set<UUID>()
        result.widgets = try widgets.map { item in
            var widget = item
            if !widgetIDs.insert(widget.id).inserted { widget.id = UUID(); widgetIDs.insert(widget.id) }
            widget.x = try clamp(item.x, -100000...100000)
            widget.y = try clamp(item.y, -100000...100000)
            widget.width = try clamp(item.width, 180...800)
            widget.height = try clamp(item.height, 140...800)
            widget.opacity = try clamp(item.opacity, 0.1...1)
            widget.notes = String(item.notes.prefix(100000))
            return widget
        }
        return result
    }
}

public enum SettingsError: LocalizedError {
    case unsupportedVersion(Int), invalidNumber, tooManyWidgets, tooLarge
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Unsupported settings version: \(version)."
        case .invalidNumber: return "Settings contain a non-finite number."
        case .tooManyWidgets: return "A maximum of 50 widgets is supported."
        case .tooLarge: return "The settings file exceeds the 2 MB limit."
        }
    }
}

public final class SettingsStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "BetterApple.settings.v1") {
        self.defaults = defaults
        self.key = key
    }
    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key), let settings = try? importSettings(data) else { return AppSettings() }
        return settings
    }
    public func save(_ settings: AppSettings) throws { defaults.set(try export(settings), forKey: key) }
    public func export(_ settings: AppSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings.validated())
        guard data.count <= 2 * 1024 * 1024 else { throw SettingsError.tooLarge }
        return data
    }
    public func importSettings(_ data: Data) throws -> AppSettings {
        guard data.count <= 2 * 1024 * 1024 else { throw SettingsError.tooLarge }
        // Merge partial documents with defaults so adding settings remains backwards compatible.
        let supplied = try JSONSerialization.jsonObject(with: data)
        guard let supplied = supplied as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected a settings object."))
        }
        let baseline = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
        func merged(_ defaults: [String: Any], _ values: [String: Any]) -> [String: Any] {
            var result = defaults
            for (key, value) in values {
                if let nested = value as? [String: Any], let prior = result[key] as? [String: Any] { result[key] = merged(prior, nested) }
                else { result[key] = value }
            }
            return result
        }
        var document = merged(baseline, supplied)
        if let items = supplied["widgets"] as? [[String: Any]] {
            document["widgets"] = try items.map { item in
                guard let rawKind = item["kind"] as? String, let kind = WidgetKind(rawValue: rawKind) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown widget kind."))
                }
                let template = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetConfiguration(kind: kind))) as! [String: Any]
                return merged(template, item)
            }
        }
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: document))
        return try decoded.validated()
    }
}
