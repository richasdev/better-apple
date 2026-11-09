import AppKit
import Combine

protocol NativeDockPreferenceAccess: Sendable {
    func readAutohide() async throws -> Bool
    func writeAutohide(_ value: Bool) async throws
}

enum NativeDockError: LocalizedError {
    case denied, verificationFailed, invalidResponse, journalFailed
    case scripting(Int, String)
    var errorDescription: String? {
        switch self {
        case .denied:
            return "Automation access to System Events was denied. Allow BetterApple in System Settings → Privacy & Security → Automation, then try again."
        case .verificationFailed:
            return "macOS did not confirm the Dock setting. Your previous setting is saved so it can be restored."
        case .invalidResponse:
            return "System Events returned an unexpected Dock setting. No replacement was confirmed."
        case .journalFailed:
            return "Your previous Dock setting could not be saved. The native Dock was not changed by this request."
        case .scripting(let code, let message):
            return code == -1712 ? "System Events did not respond in time. If macOS asked for Automation permission, allow it, then try again. Your saved Dock setting is kept." : message
        }
    }
}

/// Uses System Events' public Dock Preferences Suite. No preferences files,
/// process termination or Accessibility automation are used.
struct SystemEventsNativeDockAccess: NativeDockPreferenceAccess {
    private static let queue = AppleScriptExecution.queue
    func readAutohide() async throws -> Bool { try await execute("return autohide of dock preferences") }
    func writeAutohide(_ value: Bool) async throws {
        let actual = try await execute("set autohide of dock preferences to \(value ? "true" : "false")\nreturn autohide of dock preferences")
        guard actual == value else { throw NativeDockError.verificationFailed }
    }
    private func execute(_ operation: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                let source = "with timeout of 10 seconds\ntell application id \"com.apple.systemevents\"\n\(operation)\nend tell\nend timeout"
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: NativeDockError.invalidResponse); return
                }
                var error: NSDictionary?
                let descriptor = script.executeAndReturnError(&error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
                    let message = (error[NSAppleScript.errorMessage] as? String) ?? "The macOS Dock setting could not be updated."
                    continuation.resume(throwing: code == -1743 ? NativeDockError.denied : NativeDockError.scripting(code, message))
                } else if let value = Self.boolean(from: descriptor) {
                    continuation.resume(returning: value)
                } else { continuation.resume(throwing: NativeDockError.invalidResponse) }
            }
        }
    }

    /// AppleScript booleans arrive as `typeTrue`/`typeFalse` ('true'/'fals'),
    /// not `typeBoolean`. Requiring only `typeBoolean` rejected every real
    /// System Events reply, so Replace macOS Dock never wrote autohide.
    nonisolated static func boolean(from descriptor: NSAppleEventDescriptor) -> Bool? {
        switch descriptor.descriptorType {
        case typeTrue: return true
        case typeFalse: return false
        case typeBoolean: return descriptor.booleanValue
        default: return nil
        }
    }
}

/// Transactional ownership of one user preference. A recorded baseline survives
/// failed writes and crashes; retries never replace it with our own changed value.
@MainActor
final class NativeDockService: ObservableObject {
    @Published private(set) var desiredEnabled: Bool
    @Published private(set) var isActive = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private var previousAutohide: Bool?
    var onActivate: (() -> Void)?
    var hasPendingRestoration: Bool { previousAutohide != nil && !isActive }
    private let defaults: UserDefaults
    private let access: any NativeDockPreferenceAccess
    private let flushJournal: @MainActor () -> Bool
    private var tail: Task<Void, Error>?
    private var revision: UInt64 = 0
    private static let wantedKey = "nativeDock.replacementWanted"
    private static let previousKey = "nativeDock.previousAutohide"

    init(defaults: UserDefaults = .standard, access: any NativeDockPreferenceAccess = SystemEventsNativeDockAccess(), journalFlush: (@MainActor () -> Bool)? = nil) {
        self.defaults = defaults; self.access = access
        flushJournal = journalFlush ?? { defaults.synchronize() }
        desiredEnabled = defaults.bool(forKey: Self.wantedKey)
        previousAutohide = defaults.object(forKey: Self.previousKey) as? Bool
    }

    func setEnabled(_ enabled: Bool) async throws {
        try await enqueue {
            if enabled { try await self.activate() }
            else { try await self.restore(keepDesired: false) }
        }
    }

    func activateIfRequested() async {
        guard desiredEnabled else { return }
        do { try await setEnabled(true) } catch { /* The published error is shown in Settings. */ }
    }

    /// The caller waits for this result before normal termination. Failed restore
    /// keeps both recovery data and the user's replacement choice intact.
    func restoreForTermination() async -> Bool {
        do { try await enqueue { try await self.restore(keepDesired: true) }; return true }
        catch { return false }
    }

    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        revision &+= 1
        let current = revision
        let preceding = tail
        isBusy = true
        let task = Task { @MainActor in
            if let preceding { _ = try? await preceding.value }
            try await operation()
        }
        tail = task
        do {
            try await task.value
            if revision == current { errorMessage = nil; tail = nil; isBusy = false }
        } catch {
            if revision == current { errorMessage = error.localizedDescription; tail = nil; isBusy = false }
            throw error
        }
    }

    private func activate() async throws {
        let actual = try await access.readAutohide()
        if previousAutohide == nil {
            previousAutohide = actual
            defaults.set(actual, forKey: Self.previousKey)
        }
        // One explicit transaction boundary, never polling: flush the best-effort
        // crash journal before external mutation. This is not a power-loss guarantee.
        guard flushJournal() else { throw NativeDockError.journalFailed }
        try await access.writeAutohide(true)
        guard try await access.readAutohide() else { throw NativeDockError.verificationFailed }
        desiredEnabled = true
        defaults.set(true, forKey: Self.wantedKey)
        isActive = true
        onActivate?()
    }

    private func restore(keepDesired: Bool) async throws {
        if let original = previousAutohide {
            try await access.writeAutohide(original)
            guard try await access.readAutohide() == original else { throw NativeDockError.verificationFailed }
            previousAutohide = nil
            defaults.removeObject(forKey: Self.previousKey)
        }
        isActive = false
        if !keepDesired {
            desiredEnabled = false
            defaults.set(false, forKey: Self.wantedKey)
        }
    }
}
