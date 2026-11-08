import Foundation

/// Finite choreography for a real window and its content. Zero motion is a complete plan,
/// rather than a very fast animation, so accessibility and disabled motion stay deterministic.
public struct SurfaceMotionPlan: Equatable, Sendable {
    public let windowDuration: TimeInterval
    public let contentDuration: TimeInterval
    public let revealDelay: TimeInterval

    public static func island(expanded: Bool, requestedDuration: TimeInterval, reduceMotion: Bool) -> Self {
        guard !reduceMotion else { return .init(windowDuration: 0, contentDuration: 0, revealDelay: 0) }
        let requested = requestedDuration.isFinite ? min(0.8, max(0, requestedDuration)) : 0.24
        let duration = expanded ? requested : requested * 0.78
        let delay = expanded ? min(0.07, duration * 0.25) : duration * 0.7
        return .init(windowDuration: duration,
                     contentDuration: min(expanded ? 0.18 : 0.12, max(0, duration - delay)),
                     revealDelay: delay)
    }
}
