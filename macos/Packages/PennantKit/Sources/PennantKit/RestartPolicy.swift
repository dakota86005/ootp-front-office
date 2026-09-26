/// When a crashed server is started again, and when the app stops trying (SWIFTUI_REBUILD.md section 5.3, step 2):
/// restarts wait 1, 2, 4 … seconds, never more than 30, and five crashes inside two minutes stop the restarts, so
/// the app shows the problem instead of looping.
///
/// The delay doubles with each crash in a row. A server that stayed up for a whole window before crashing starts
/// the count again, so a crash a week does not wait 30 seconds. Times are passed in, so the schedule is tested
/// without waiting.
public struct RestartPolicy: Sendable, Equatable {
    public var baseDelay: Duration
    public var maxDelay: Duration
    public var maxCrashes: Int
    public var window: Duration

    /// The crashes inside the window, oldest first.
    public private(set) var recentCrashes: [ContinuousClock.Instant] = []
    /// Crashes in a row, without a whole window of running between them.
    public private(set) var consecutive = 0

    public init(
        baseDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(30),
        maxCrashes: Int = 5,
        window: Duration = .seconds(120)
    ) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxCrashes = maxCrashes
        self.window = window
    }

    public enum Decision: Sendable, Equatable {
        /// Start it again after this wait; `attempt` counts the crashes in a row.
        case restart(after: Duration, attempt: Int)
        /// Too many crashes inside the window: stop and show the problem.
        case giveUp(crashes: Int)
    }

    /// The wait before restart number `attempt` (1-based): base × 2^(attempt − 1), capped.
    public func delay(forAttempt attempt: Int) -> Duration {
        var delay = baseDelay
        for _ in 1..<max(attempt, 1) {
            delay *= 2
            if delay >= maxDelay { return maxDelay }
        }
        return min(delay, maxDelay)
    }

    /// Records a crash at `now`. `upFor` is how long that server had been running (nil if it never became ready).
    public mutating func recordCrash(at now: ContinuousClock.Instant, upFor: Duration?) -> Decision {
        if let upFor, upFor >= window { consecutive = 0 }
        consecutive += 1
        recentCrashes = recentCrashes.filter { now - $0 < window } + [now]
        if recentCrashes.count >= maxCrashes { return .giveUp(crashes: recentCrashes.count) }
        return .restart(after: delay(forAttempt: consecutive), attempt: consecutive)
    }

    /// Forgets every crash (the GM chose Try Again, or the app started the server afresh).
    public mutating func reset() {
        recentCrashes = []
        consecutive = 0
    }
}
