import Foundation
import SwiftUI

enum DesktopWidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, analogClock, calendar, events, calculator, music, battery, system, notes, timer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .analogClock: return "Analog Clock"
        case .events: return "Upcoming Events"
        case .system: return "CPU & Memory"
        default: return rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .clock, .analogClock: return "clock"
        case .calendar, .events: return "calendar"
        case .calculator: return "plus.forwardslash.minus"
        case .music: return "music.note"
        case .battery: return "battery.100percent"
        case .system: return "cpu"
        case .notes: return "note.text"
        case .timer: return "timer"
        }
    }
}

enum DesktopWidgetTheme: String, Codable, CaseIterable, Identifiable {
    case automatic, light, dark
    var id: String { rawValue }
}

enum DesktopWidgetAccent: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, orange, green, graphite
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .graphite: return .gray
        }
    }
}

/// Presentation preferences are independent of sampling. A widget never creates a service timer.
struct WidgetDisplayOptions: Codable, Equatable {
    var showSeconds = false
    var use24Hour = true
    var showDate = true
    var clockTimeZoneIdentifier: String?
    var showArtwork = true
    var showArtist = true
    var showProgress = true
    var showCPU = true
    var showMemory = true
    var showChargingState = true
    var eventLimit = 3

    init() {}
    private enum CodingKeys: String, CodingKey {
        case showSeconds, use24Hour, showDate, clockTimeZoneIdentifier, showArtwork, showArtist
        case showProgress, showCPU, showMemory, showChargingState, eventLimit
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showSeconds = try values.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? false
        use24Hour = try values.decodeIfPresent(Bool.self, forKey: .use24Hour) ?? true
        showDate = try values.decodeIfPresent(Bool.self, forKey: .showDate) ?? true
        clockTimeZoneIdentifier = try values.decodeIfPresent(String.self, forKey: .clockTimeZoneIdentifier)
        showArtwork = try values.decodeIfPresent(Bool.self, forKey: .showArtwork) ?? true
        showArtist = try values.decodeIfPresent(Bool.self, forKey: .showArtist) ?? true
        showProgress = try values.decodeIfPresent(Bool.self, forKey: .showProgress) ?? true
        showCPU = try values.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        showMemory = try values.decodeIfPresent(Bool.self, forKey: .showMemory) ?? true
        showChargingState = try values.decodeIfPresent(Bool.self, forKey: .showChargingState) ?? true
        eventLimit = try values.decodeIfPresent(Int.self, forKey: .eventLimit) ?? 3
    }
    var timeZone: TimeZone { clockTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent }
}

struct WidgetLayoutPreferences: Codable, Equatable {
    var snapToGrid = false
    var gridSize = 20.0
    func validated() throws -> Self {
        guard gridSize.isFinite, (8...64).contains(gridSize) else { throw WidgetValidationError.invalidLayout }
        return self
    }
}

struct WidgetConfiguration: Codable, Identifiable {
    var id = UUID()
    var kind: DesktopWidgetKind
    var visible = true
    var x: Double = 80
    var y: Double = 100
    var width: Double = 300
    var height: Double = 240
    var opacity: Double = 0.95
    var theme: DesktopWidgetTheme = .automatic
    var shadow = true
    var border = true
    var note = ""
    var accent: DesktopWidgetAccent?
    // Optional additions keep every v1 layout and exported suite decodable.
    var title: String?
    var fontSize: Double?
    var options: WidgetDisplayOptions?
    var displayTitle: String {
        let custom = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? kind.title : custom
    }
    var displayOptions: WidgetDisplayOptions { options ?? WidgetDisplayOptions() }
    var textSize: Double {
        if let fontSize { return fontSize }
        switch kind {
        case .clock, .analogClock: return 42
        case .calendar: return 64
        case .battery: return 48
        case .timer: return 44
        case .notes, .system, .events, .calculator: return 14
        case .music: return 16
        }
    }
    func validated() throws -> Self {
        guard x.isFinite, y.isFinite, (220...800).contains(width), (160...800).contains(height),
              (0.2...1).contains(opacity) else { throw WidgetValidationError.invalidGeometry }
        guard (title?.count ?? 0) <= 80, note.count <= 100000,
              fontSize.map({ $0.isFinite && (10...64).contains($0) }) ?? true,
              (1...8).contains(displayOptions.eventLimit),
              displayOptions.clockTimeZoneIdentifier.map({ TimeZone(identifier: $0) != nil }) ?? true,
              kind != .system || displayOptions.showCPU || displayOptions.showMemory else { throw WidgetValidationError.invalidOptions }
        return self
    }
    func sanitized() -> Self {
        var value = self
        value.x = x.isFinite ? x : 80; value.y = y.isFinite ? y : 100
        value.width = width.isFinite ? min(800, max(220, width)) : 300
        value.height = height.isFinite ? min(800, max(160, height)) : 240
        value.opacity = opacity.isFinite ? min(1, max(0.2, opacity)) : 0.95
        value.title = title.map { String($0.prefix(80)) }
        value.note = String(note.prefix(100000))
        if let size = fontSize { value.fontSize = size.isFinite ? min(64, max(10, size)) : nil }
        if var options {
            if let zone = options.clockTimeZoneIdentifier, TimeZone(identifier: zone) == nil { options.clockTimeZoneIdentifier = nil }
            options.eventLimit = min(8, max(1, options.eventLimit))
            if kind == .system && !options.showCPU && !options.showMemory { options.showCPU = true }
            value.options = options
        }
        return value
    }
}

enum WidgetValidationError: LocalizedError {
    case invalidGeometry, invalidOptions, invalidLayout
    var errorDescription: String? {
        switch self {
        case .invalidGeometry: return "A widget has invalid size, position or opacity."
        case .invalidOptions: return "A widget has an invalid title, font size, time zone or display option."
        case .invalidLayout: return "The widget grid size must be between 8 and 64 points."
        }
    }
}
