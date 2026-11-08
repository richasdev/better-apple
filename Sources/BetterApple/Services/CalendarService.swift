import AppKit
import Combine
import EventKit

struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

/// EventKit is instantiated lazily: launching BetterApple never requests calendar access.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var errorMessage: String?
    private let worker = CalendarStoreWorker()
    private var observer: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var active = false
    private var refreshTask: Task<Void, Never>?
    private var revision = 0

    func requestAccess() async {
        do {
            let granted = try await worker.requestAccess()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            errorMessage = granted ? nil : "Calendar access was not granted. You can enable it in System Settings."
            if granted { refresh() }
        } catch { errorMessage = error.localizedDescription }
    }

    func start() {
        guard !active else { return }
        active = true
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active else { return }
                self.refresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active else { return }
                self.refresh()
            }
        }
        refresh()
    }

    func stop() {
        active = false
        revision += 1
        refreshTask?.cancel()
        refreshTask = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        observer = nil
        wakeObserver = nil
    }

    func refresh() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        refreshTask?.cancel()
        revision += 1
        guard authorizationStatus == .fullAccess else { events = []; return }
        let currentRevision = revision
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(604800)
        worker.fetch(from: now, to: end) { [weak self] result in
            Task { @MainActor in
                guard let self, self.revision == currentRevision else { return }
                self.events = Array(result)
                self.errorMessage = nil
                // One deadline, rather than a repeating timer, expires the next event.
                if self.active {
                    let next = result.map(\.endDate).min() ?? end
                    self.refreshTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(max(1, next.timeIntervalSinceNow)) * 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        self?.refresh()
                    }
                }
            }
        }
    }

    func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    deinit {
        refreshTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}

/// EKEventStore is lazily created and used only on this worker's serial queue.
/// Only value snapshots cross back to the UI actor.
private final class CalendarStoreWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.betterapple.calendar", qos: .utility)
    private var store: EKEventStore?

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let created = EKEventStore()
        store = created
        return created
    }

    func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                eventStore().requestFullAccessToEvents { granted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
        }
    }

    func fetch(from start: Date, to end: Date, completion: @escaping @Sendable ([CalendarEvent]) -> Void) {
        queue.async { [self] in
            let store = eventStore()
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let result = store.events(matching: predicate)
                .filter { $0.endDate > start }
                .sorted { $0.startDate < $1.startDate }
                .prefix(50)
                .map { CalendarEvent(id: ($0.eventIdentifier ?? UUID().uuidString) + String($0.startDate.timeIntervalSince1970), title: $0.title ?? "Untitled event", startDate: $0.startDate, endDate: $0.endDate, isAllDay: $0.isAllDay) }
            completion(Array(result))
        }
    }
}
