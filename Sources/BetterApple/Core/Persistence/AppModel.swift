import AppKit
import Combine
import BetterAppleCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            if !replacingSettings && visualChanged(from: oldValue, to: settings) { settings.appearance = .custom }
            do { try store.save(settings); persistenceError = nil }
            catch { persistenceError = error.localizedDescription }
        }
    }
    @Published var persistenceError: String?
    private let store: SettingsStore
    private var replacingSettings = false
    init(defaults: UserDefaults = .standard) {
        let store = SettingsStore(defaults: defaults)
        self.store = store
        settings = store.load()
    }
    func applyPreset(_ preset: AppearancePreset) {
        replacingSettings = true
        settings.applyPreset(preset)
        replacingSettings = false
    }
    func replaceSettings(_ value: AppSettings) {
        replacingSettings = true
        settings = value
        replacingSettings = false
    }
    func enableCameraExperienceIfNeeded(defaults: UserDefaults) {
        let key = "island.cameraExperience.v1"
        guard !defaults.bool(forKey: key) else { return }
        if let existing = defaults.data(forKey: "BetterApple.settings.v1") {
            do { _ = try store.importSettings(existing) }
            catch { persistenceError = "Camera setup kept the existing configuration unchanged: \(error.localizedDescription)"; return }
        }
        var updated = settings
        updated.island.placementMode = .camera
        updated.island.enabled = true
        updated.island.hoverToExpand = true
        if updated.island.autoCloseDelay == 0 { updated.island.autoCloseDelay = 1 }
        replaceSettings(updated)
        if persistenceError == nil { defaults.set(true, forKey: key) }
    }
    private func visualChanged(from old: AppSettings, to new: AppSettings) -> Bool {
        old.island.placementMode != new.island.placementMode || old.island.visual != new.island.visual || old.island.width != new.island.width || old.island.height != new.island.height ||
        old.island.expandedWidth != new.island.expandedWidth || old.island.expandedHeight != new.island.expandedHeight || old.island.minimal != new.island.minimal
    }
    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "BetterApple-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(settings).write(to: url, options: .atomic) }
        catch { persistenceError = error.localizedDescription }
    }
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { settings = try store.importSettings(Data(contentsOf: url)) }
        catch { persistenceError = error.localizedDescription }
    }
}
