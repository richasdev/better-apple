import AppKit
import Carbon
import Combine
import SwiftUI

/// One optional registered hotkey, never a global keyboard monitor or event tap.
/// Carbon registration does not require Accessibility or Input Monitoring access.
@MainActor
final class GlobalShortcutService: ObservableObject {
    enum Key: String, CaseIterable, Identifiable {
        case b, i, space
        var id: String { rawValue }
        var title: String {
            switch self { case .b: return "B"; case .i: return "I"; case .space: return "Space" }
        }
        fileprivate var virtualKey: UInt32 {
            switch self {
            case .b: return UInt32(kVK_ANSI_B)
            case .i: return UInt32(kVK_ANSI_I)
            case .space: return UInt32(kVK_Space)
            }
        }
    }

    enum Modifiers: String, CaseIterable, Identifiable {
        case controlOption, commandShift, controlShift
        var id: String { rawValue }
        var title: String {
            switch self {
            case .controlOption: return "Control + Option (⌃⌥)"
            case .commandShift: return "Command + Shift (⇧⌘)"
            case .controlShift: return "Control + Shift (⌃⇧)"
            }
        }
        fileprivate var carbonFlags: UInt32 {
            switch self {
            case .controlOption: return UInt32(controlKey | optionKey)
            case .commandShift: return UInt32(cmdKey | shiftKey)
            case .controlShift: return UInt32(controlKey | shiftKey)
            }
        }
    }

    @Published var enabled: Bool { didSet { if enabled != oldValue { reconfigure() } } }
    @Published var key: Key { didSet { if key != oldValue { reconfigure() } } }
    @Published var modifiers: Modifiers { didSet { if modifiers != oldValue { reconfigure() } } }
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRegistered = false
    var onTrigger: (() -> Void)?
    private let defaults: UserDefaults
    private var registration: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handlerContext: ShortcutHandlerContext?
    private static var nextIdentifier: UInt32 = 1
    private let identifier: EventHotKeyID

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        identifier = EventHotKeyID(signature: 0x4241504C, id: Self.nextIdentifier) // BAPL
        Self.nextIdentifier &+= 1
        enabled = defaults.bool(forKey: "shortcut.enabled")
        key = Key(rawValue: defaults.string(forKey: "shortcut.key") ?? "") ?? .b
        modifiers = Modifiers(rawValue: defaults.string(forKey: "shortcut.modifiers") ?? "") ?? .controlOption
        configure()
    }

    func retryRegistration() { configure() }

    /// Explicit teardown for application termination. Does not change the preference.
    func stop() {
        if let registration { UnregisterEventHotKey(registration) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        registration = nil
        eventHandler = nil
        handlerContext = nil
        isRegistered = false
    }

    private func reconfigure() {
        defaults.set(enabled, forKey: "shortcut.enabled")
        defaults.set(key.rawValue, forKey: "shortcut.key")
        defaults.set(modifiers.rawValue, forKey: "shortcut.modifiers")
        configure()
    }

    private func configure() {
        stop()
        errorMessage = nil
        guard enabled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = ShortcutHandlerContext(identifier: identifier, service: self)
        handlerContext = context
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), betterAppleShortcutHandler, 1, &eventType, Unmanaged.passUnretained(context).toOpaque(), &eventHandler)
        guard handlerStatus == noErr else {
            stop()
            errorMessage = "Unable to install the shortcut handler (\(handlerStatus))."
            return
        }
        let registrationStatus = RegisterEventHotKey(key.virtualKey, modifiers.carbonFlags, identifier, GetApplicationEventTarget(), 0, &registration)
        guard registrationStatus == noErr else {
            stop()
            errorMessage = registrationStatus == eventHotKeyExistsErr
                ? "This shortcut is already in use. Choose another key or modifier combination."
                : "macOS could not register this shortcut (\(registrationStatus)). Try another combination."
            return
        }
        isRegistered = true
    }

    fileprivate func handleHotkey(_ identifier: EventHotKeyID) {
        guard enabled, isRegistered, identifier.signature == self.identifier.signature,
              identifier.id == self.identifier.id else { return }
        onTrigger?()
    }

    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

/// A retained registration context prevents use-after-free and filters events for
/// other hotkeys before returning them to Carbon's next application handler.
private final class ShortcutHandlerContext {
    let identifier: EventHotKeyID
    @MainActor weak var service: GlobalShortcutService?
    @MainActor init(identifier: EventHotKeyID, service: GlobalShortcutService) {
        self.identifier = identifier
        self.service = service
    }
}

private func betterAppleShortcutHandler(_ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard status == noErr else { return status }
    let owner = Unmanaged<ShortcutHandlerContext>.fromOpaque(context).takeUnretainedValue()
    guard identifier.signature == owner.identifier.signature, identifier.id == owner.identifier.id else {
        return OSStatus(eventNotHandledErr)
    }
    Task { @MainActor [weak owner] in owner?.service?.handleHotkey(identifier) }
    return noErr
}

struct ShortcutSettingsView: View {
    @ObservedObject var service: GlobalShortcutService

    var body: some View {
        Form {
            Section("Dynamic Island") {
                Toggle("Enable global shortcut", isOn: $service.enabled)
                Picker("Modifiers", selection: $service.modifiers) {
                    ForEach(GlobalShortcutService.Modifiers.allCases) { choice in Text(choice.title).tag(choice) }
                }
                Picker("Key", selection: $service.key) {
                    ForEach(GlobalShortcutService.Key.allCases) { choice in Text(choice.title).tag(choice) }
                }
                Text("Toggle the Dynamic Island from any application. Uses physical B, I or Space keys; no Accessibility permission is needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = service.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Retry registration") { service.retryRegistration() }
                } else if service.isRegistered {
                    Label("Shortcut active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
    }
}
