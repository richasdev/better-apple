import AppKit

enum DockPresentation: String, Codable, CaseIterable, Identifiable {
    case rail, floating
    var id: String { rawValue }
    var title: String { self == .rail ? "Continuous rail" : "Floating tiles" }
}

enum DockModule: String, Codable, CaseIterable, Identifiable {
    case apps, music, timer, battery, note
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apps: return "Applications"
        case .music: return "Music"
        case .timer: return "Timer"
        case .battery: return "Battery"
        case .note: return "Quick note"
        }
    }
    var symbol: String {
        switch self {
        case .apps: return "app.dashed"
        case .music: return "music.note"
        case .timer: return "timer"
        case .battery: return "battery.100percent"
        case .note: return "note.text"
        }
    }
    var tileWidth: CGFloat {
        switch self {
        case .apps: return 0
        case .music: return 220
        case .timer: return 170
        case .battery: return 112
        case .note: return 210
        }
    }
    static let tileHeight: CGFloat = 92
}

@MainActor
struct DockActivitySources {
    let music: MusicService
    let system: SystemStatusService
    let timer: TimerService
}

/// Identical logical sizes are used by AppKit panels and SwiftUI scroll content.
struct DockContentMetrics {
    let icon: DockLayoutMetrics
    let modules: [DockModule]
    let applicationCount: Int
    let spacing: CGFloat
    let vertical: Bool
    init(_ preferences: DockPreferences, applicationCount: Int, reduceMotion: Bool) {
        icon = DockLayoutMetrics(preferences, reduceMotion: reduceMotion)
        let enabled = Set(preferences.enabledModules)
        modules = (preferences.moduleOrder + DockModule.allCases).reduce(into: []) { result, module in
            if enabled.contains(module), !result.contains(module) { result.append(module) }
        }
        self.applicationCount = max(1, applicationCount)
        spacing = preferences.spacing
        vertical = preferences.position != .bottom
    }
    var appPadding: CGFloat { modules.count > 1 ? icon.padding : 0 }
    var hasCards: Bool { modules.contains { $0 != .apps } }
    var crossContent: CGFloat {
        max(vertical ? icon.itemWidth : icon.itemHeight,
            modules.filter { $0 != .apps }.map { vertical ? $0.tileWidth : DockModule.tileHeight }.max() ?? 0)
    }
    var length: CGFloat {
        guard !modules.isEmpty else { return 160 + icon.padding * 2 }
        let lengths = modules.map { module -> CGFloat in
            if module == .apps {
                return CGFloat(applicationCount) * (vertical ? icon.itemHeight : icon.itemWidth) + CGFloat(applicationCount - 1) * spacing + appPadding * 2
            }
            return vertical ? DockModule.tileHeight : module.tileWidth
        }
        return lengths.reduce(0, +) + CGFloat(modules.count - 1) * spacing + icon.padding * 2
    }
    var thickness: CGFloat {
        vertical ? crossContent + icon.horizontalPadding(vertical: true) * 2 : crossContent + icon.topPadding(vertical: false) + icon.bottomPadding(vertical: false)
    }
}
