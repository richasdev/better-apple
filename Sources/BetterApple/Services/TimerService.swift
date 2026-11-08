import AppKit
import Combine

enum TimerCompletionSound: String, Codable, CaseIterable, Identifiable {
    case glass, ping, silent
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var soundName: String? {
        switch self { case .glass: return "Glass"; case .ping: return "Ping"; case .silent: return nil }
    }
}

struct TimerPreferences: Codable, Equatable {
    var label = ""
    var presetMinutes = [1, 5, 15, 25]
    var completionSound: TimerCompletionSound = .glass

    func normalized() -> TimerPreferences {
        var value = self
        value.label = String(label.prefix(80))
        value.presetMinutes = Array(Set(presetMinutes.filter { (1...1440).contains($0) })).sorted()
        if value.presetMinutes.isEmpty { value.presetMinutes = [1, 5, 15, 25] }
        value.presetMinutes = Array(value.presetMinutes.prefix(8))
        return value
    }
}

/// Uses an absolute deadline so display sleep and hidden surfaces do not cause drift.
@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var didComplete = false
    @Published var preferences: TimerPreferences {
        didSet {
            let normalized = preferences.normalized()
            if preferences != normalized { preferences = normalized }
            if let data = try? JSONEncoder().encode(normalized) { defaults.set(data, forKey: "timer.preferences") }
        }
    }
    var label: String {
        get { preferences.label }
        set { preferences.label = newValue }
    }
    var presetMinutes: [Int] { preferences.presetMinutes }
    var completionSound: TimerCompletionSound {
        get { preferences.completionSound }
        set { preferences.completionSound = newValue }
    }
    var progress: Double { duration > 0 ? min(1, max(0, (duration - remaining) / duration)) : 0 }
    private let defaults: UserDefaults
    private var deadline: Date?
    private var completionTask: Task<Void, Never>?
    private var displayTimer: Timer?
    private var visible = false
    private var wakeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = (defaults.data(forKey: "timer.preferences").flatMap { try? JSONDecoder().decode(TimerPreferences.self, from: $0) } ?? TimerPreferences()).normalized()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateRemaining() }
        }
    }

    func addPreset(minutes: Int) {
        guard (1...1440).contains(minutes), !presetMinutes.contains(minutes), presetMinutes.count < 8 else { return }
        preferences.presetMinutes.append(minutes)
    }
    func removePreset(minutes: Int) {
        guard presetMinutes.count > 1 else { return }
        preferences.presetMinutes.removeAll { $0 == minutes }
    }
    func restart() {
        let previousDuration = duration
        guard previousDuration > 0 else { return }
        start(seconds: previousDuration)
    }
    func extend(seconds: TimeInterval) {
        guard (isRunning || isPaused), seconds.isFinite, seconds > 0 else { return }
        updateRemaining()
        guard isRunning || isPaused else { return }
        let added = min(seconds, max(0, 604800 - duration))
        guard added > 0 else { return }
        duration += added
        remaining += added
        if let deadline { self.deadline = deadline.addingTimeInterval(added); scheduleCompletion() }
    }
    func dismissCompletion() { cancel() }

    func start(seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0, seconds <= 604800 else { return }
        cancel()
        duration = seconds
        remaining = seconds
        didComplete = false
        isRunning = true
        deadline = Date().addingTimeInterval(seconds)
        scheduleCompletion()
        updateDisplayTimer()
    }

    func pause() {
        guard isRunning else { return }
        updateRemaining()
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        deadline = nil
        completionTask?.cancel()
        completionTask = nil
        updateDisplayTimer()
    }

    func resume() {
        guard isPaused, remaining > 0 else { return }
        deadline = Date().addingTimeInterval(remaining)
        isPaused = false
        isRunning = true
        scheduleCompletion()
        updateDisplayTimer()
    }

    func cancel() {
        completionTask?.cancel()
        completionTask = nil
        displayTimer?.invalidate()
        displayTimer = nil
        deadline = nil
        remaining = 0
        duration = 0
        isRunning = false
        isPaused = false
        didComplete = false
    }

    func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        updateRemaining()
        updateDisplayTimer()
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        guard let deadline else { return }
        completionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.updateRemaining()
            // Reschedule when wall-clock corrections put the deadline in the future.
            if self?.isRunning == true { self?.scheduleCompletion() }
        }
    }

    private func updateRemaining() {
        guard isRunning, let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        if remaining == 0 {
            isRunning = false
            isPaused = false
            didComplete = true
            self.deadline = nil
            completionTask?.cancel()
            completionTask = nil
            displayTimer?.invalidate()
            displayTimer = nil
            if let name = completionSound.soundName { NSSound(named: NSSound.Name(name))?.play() }
            let announcement = label.isEmpty ? "Timer finished" : "\(label) finished"
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private func updateDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
        guard visible, isRunning else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateRemaining() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    deinit {
        completionTask?.cancel()
        displayTimer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
