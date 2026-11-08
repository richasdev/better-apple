import AppKit
import SwiftUI

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, left, right
    var id: String { rawValue }
}
enum DockTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
}
enum DockMaterial: String, Codable, CaseIterable, Identifiable {
    case glass, solid
    var id: String { rawValue }
}
enum DockAccent: String, Codable, CaseIterable, Identifiable {
    case system, mint, blue, purple, orange, pink
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .system: return .accentColor
        case .mint: return .mint
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

struct DockPreferences: Codable, Equatable {
    var enabled = false
    var iconSize: Double = 48
    var spacing: Double = 10
    var opacity: Double = 0.9
    var position: DockPosition = .bottom
    var autoHide = false
    var screenID: String = ""
    var applicationPaths: [String] = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Music.app"]
    var theme: DockTheme = .system
    var material: DockMaterial = .glass
    var accent: DockAccent = .system
    var cornerRadius: Double = 22
    var magnification: Double = 1.16
    var animationDuration: Double = 0.16
    var showLabels = false
    var showRunningApplications = false
    var allDisplays = false

    init() {}
    private enum CodingKeys: String, CodingKey {
        case enabled, iconSize, spacing, opacity, position, autoHide, screenID, applicationPaths
        case theme, material, accent, cornerRadius, magnification, animationDuration, showLabels, showRunningApplications, allDisplays
    }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        iconSize = try values.decodeIfPresent(Double.self, forKey: .iconSize) ?? iconSize
        spacing = try values.decodeIfPresent(Double.self, forKey: .spacing) ?? spacing
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
        position = try values.decodeIfPresent(DockPosition.self, forKey: .position) ?? position
        autoHide = try values.decodeIfPresent(Bool.self, forKey: .autoHide) ?? autoHide
        screenID = try values.decodeIfPresent(String.self, forKey: .screenID) ?? screenID
        applicationPaths = try values.decodeIfPresent([String].self, forKey: .applicationPaths) ?? applicationPaths
        theme = try values.decodeIfPresent(DockTheme.self, forKey: .theme) ?? theme
        material = try values.decodeIfPresent(DockMaterial.self, forKey: .material) ?? material
        accent = try values.decodeIfPresent(DockAccent.self, forKey: .accent) ?? accent
        cornerRadius = try values.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        magnification = try values.decodeIfPresent(Double.self, forKey: .magnification) ?? magnification
        animationDuration = try values.decodeIfPresent(Double.self, forKey: .animationDuration) ?? animationDuration
        showLabels = try values.decodeIfPresent(Bool.self, forKey: .showLabels) ?? showLabels
        showRunningApplications = try values.decodeIfPresent(Bool.self, forKey: .showRunningApplications) ?? showRunningApplications
        allDisplays = try values.decodeIfPresent(Bool.self, forKey: .allDisplays) ?? allDisplays
    }

    /// Repair safe numeric ranges, but reject malformed or oversized application lists.
    func validated() throws -> DockPreferences {
        guard [iconSize, spacing, opacity, cornerRadius, magnification, animationDuration].allSatisfy(\.isFinite), applicationPaths.count <= 100,
              applicationPaths.allSatisfy({ $0.hasPrefix("/") && $0.hasSuffix(".app") && $0.utf8.count <= 4096 }) else { throw CocoaError(.coderInvalidValue) }
        var result = self
        result.iconSize = min(80, max(24, iconSize)); result.spacing = min(24, max(0, spacing))
        result.opacity = min(1, max(0.2, opacity)); result.cornerRadius = min(40, max(0, cornerRadius))
        result.magnification = min(1.5, max(1, magnification)); result.animationDuration = min(0.5, max(0, animationDuration))
        var seen = Set<String>()
        result.applicationPaths = applicationPaths.filter { seen.insert($0).inserted }
        return result
    }
}
