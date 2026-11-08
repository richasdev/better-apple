import AppKit
import Combine

/// Uses an absolute deadline so display sleep and hidden surfaces do not cause drift.
@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var didComplete = false
    private var deadline: Date?
    private var completionTask: Task<Void, Never>?
    private var displayTimer: Timer?
    private var visible = false
    private var wakeObserver: NSObjectProtocol?

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateRemaining() }
        }
    }

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
            NSSound(named: "Glass")?.play()
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: "Timer finished", .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
