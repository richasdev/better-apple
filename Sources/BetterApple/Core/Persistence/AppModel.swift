import AppKit
import Combine
import BetterAppleCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            do { try store.save(settings); persistenceError = nil }
            catch { persistenceError = error.localizedDescription }
        }
    }
    @Published var persistenceError: String?
    private let store: SettingsStore
    init(defaults: UserDefaults = .standard) {
        let store = SettingsStore(defaults: defaults)
        self.store = store
        settings = store.load()
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
