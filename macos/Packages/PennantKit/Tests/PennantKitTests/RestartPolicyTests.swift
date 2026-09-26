import Testing
@testable import PennantKit

/// SWIFTUI_REBUILD.md section 5.3, step 2: restart after 1, 2, 4 … 30 s; stop after five crashes in two minutes.
@Suite("The restart policy")
struct RestartPolicyTests {
    let start = ContinuousClock.now

    @Test("the waits double from one second and stop growing at thirty")
    func schedule() {
        let policy = RestartPolicy()
        let waits = (1...8).map { policy.delay(forAttempt: $0) }
        #expect(waits == [1, 2, 4, 8, 16, 30, 30, 30].map { Duration.seconds($0) })
    }

    @Test("five crashes inside two minutes stop the restarts")
    func crashWindow() {
        var policy = RestartPolicy()
        var decisions: [RestartPolicy.Decision] = []
        for second in [0, 2, 5, 10, 19] {
            decisions.append(policy.recordCrash(at: start + .seconds(second), upFor: nil))
        }
        #expect(decisions == [
            .restart(after: .seconds(1), attempt: 1),
            .restart(after: .seconds(2), attempt: 2),
            .restart(after: .seconds(4), attempt: 3),
            .restart(after: .seconds(8), attempt: 4),
            .giveUp(crashes: 5),
        ])
    }

    @Test("crashes spread wider than the window keep restarting, with the wait capped")
    func spreadCrashes() {
        var policy = RestartPolicy()
        var last: RestartPolicy.Decision?
        // One crash a minute, each after a short run: never five inside two minutes
        for minute in 0..<10 {
            last = policy.recordCrash(at: start + .seconds(60 * minute), upFor: .seconds(20))
            if case .giveUp = last { Issue.record("gave up at minute \(minute)") }
        }
        #expect(last == .restart(after: .seconds(30), attempt: 10))
        #expect(policy.recentCrashes.count <= 3)
    }

    @Test("a server that ran for a whole window starts the count again")
    func stableRunResets() {
        var policy = RestartPolicy()
        _ = policy.recordCrash(at: start, upFor: nil)
        _ = policy.recordCrash(at: start + .seconds(1), upFor: nil)
        #expect(policy.consecutive == 2)
        let decision = policy.recordCrash(at: start + .seconds(600), upFor: .seconds(590))
        #expect(decision == .restart(after: .seconds(1), attempt: 1))
    }

    @Test("reset forgets every crash")
    func reset() {
        var policy = RestartPolicy()
        for second in 0..<4 { _ = policy.recordCrash(at: start + .seconds(second), upFor: nil) }
        policy.reset()
        #expect(policy.recordCrash(at: start + .seconds(5), upFor: nil) == .restart(after: .seconds(1), attempt: 1))
    }

    @Test("a crash exactly one window after the first no longer counts it")
    func windowEdge() {
        var policy = RestartPolicy()
        for second in [0, 1, 2, 3] { _ = policy.recordCrash(at: start + .seconds(second), upFor: nil) }
        let decision = policy.recordCrash(at: start + .seconds(120), upFor: nil)
        #expect(decision == .restart(after: .seconds(16), attempt: 5))
        #expect(policy.recentCrashes.count == 4)
    }
}
