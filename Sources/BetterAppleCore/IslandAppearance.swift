import Foundation

public enum SurfaceTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum SurfaceMaterial: String, Codable, CaseIterable, Identifiable, Sendable {
    case solid, glass
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum WorkspaceAccent: String, Codable, CaseIterable, Identifiable, Sendable {
    case mint, blue, purple, orange, rose, graphite
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct IslandAppearance: Codable, Equatable, Sendable {
    public var theme: SurfaceTheme = .dark
    public var material: SurfaceMaterial = .solid
    public var accent: WorkspaceAccent = .mint
    public var opacity = 0.97
    public var cornerRadius = 26.0
    public var borderVisible = true
    public var shadowVisible = true
    public var animationDuration = 0.24
    public var showModuleLabels = false
    public var compactStatus = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case theme, material, accent, opacity, cornerRadius, borderVisible, shadowVisible, animationDuration, showModuleLabels, compactStatus
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(SurfaceTheme.self, forKey: .theme) ?? .dark
        material = try values.decodeIfPresent(SurfaceMaterial.self, forKey: .material) ?? .solid
        accent = try values.decodeIfPresent(WorkspaceAccent.self, forKey: .accent) ?? .mint
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.97
        cornerRadius = try values.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 26
        borderVisible = try values.decodeIfPresent(Bool.self, forKey: .borderVisible) ?? true
        shadowVisible = try values.decodeIfPresent(Bool.self, forKey: .shadowVisible) ?? true
        animationDuration = try values.decodeIfPresent(Double.self, forKey: .animationDuration) ?? 0.24
        showModuleLabels = try values.decodeIfPresent(Bool.self, forKey: .showModuleLabels) ?? false
        compactStatus = try values.decodeIfPresent(Bool.self, forKey: .compactStatus) ?? false
    }
    public func validated() throws -> IslandAppearance {
        guard opacity.isFinite, cornerRadius.isFinite, animationDuration.isFinite else { throw SettingsError.invalidNumber }
        var result = self
        result.opacity = min(1, max(0.5, opacity))
        result.cornerRadius = min(40, max(0, cornerRadius))
        result.animationDuration = min(0.8, max(0, animationDuration))
        return result
    }
}
