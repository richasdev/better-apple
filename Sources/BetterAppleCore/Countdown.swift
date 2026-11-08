import Foundation

/// Deadline based, so sleeping or suspending the process never loses elapsed time.
/// The UI may schedule only a single completion notification and render ticks while visible.
public struct Countdown: Equatable, Sendable {
    public private(set) var deadline: Date?
    public private(set) var pausedRemaining: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public init() {}
    public var isRunning: Bool { deadline != nil }
    public var isPaused: Bool { deadline == nil && pausedRemaining > 0 }
    public func remaining(at now: Date = Date()) -> TimeInterval {
        if let deadline { return max(0, deadline.timeIntervalSince(now)) }
        return pausedRemaining
    }
    public func isFinished(at now: Date = Date()) -> Bool { deadline.map { $0 <= now } ?? false }
    public mutating func start(seconds: TimeInterval, now: Date = Date()) {
        guard seconds.isFinite && seconds > 0 else { cancel(); return }
        duration = min(seconds, 7 * 24 * 3600)
        pausedRemaining = 0
        deadline = now.addingTimeInterval(duration)
    }
    public mutating func pause(now: Date = Date()) {
        guard deadline != nil else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }
    public mutating func resume(now: Date = Date()) {
        guard deadline == nil && pausedRemaining > 0 else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        pausedRemaining = 0
    }
    public mutating func cancel() { deadline = nil; pausedRemaining = 0; duration = 0 }
}
