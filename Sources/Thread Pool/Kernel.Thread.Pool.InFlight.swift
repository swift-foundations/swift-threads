//
//  Kernel.Thread.Pool.InFlight.swift
//  swift-executors
//

import Synchronizer_Blocking

extension Kernel.Thread.Pool {
    /// Tracks admitted-but-not-yet-completed `run` calls so `shutdown()` can
    /// block until every one of them has finished before joining the
    /// underlying executor threads.
    ///
    /// `enter()` is called at the very top of `run(...)`, before the
    /// admission wait — so a call that is only *attempting* admission (not
    /// yet granted a permit) still counts. This closes the race where
    /// `shutdown()` observes zero in-flight work and proceeds to join the
    /// executor pool while a just-admitted caller has not yet reached the
    /// executor: that caller is counted from the moment it enters `run`,
    /// long before it could possibly be dropped or stranded.
    ///
    /// ## Safety Invariant
    ///
    /// `count` is read and mutated exclusively under `sync`'s mutex; every
    /// transition — `enter`, `leave`, and the zero-check in `waitUntilIdle`
    /// — is serialized through `Synchronizer.Blocking<1>`. The `leave()` ->
    /// zero transition and the `broadcast` that wakes `waitUntilIdle` are
    /// split across the lock (compute-under-lock, signal-after-unlock) to
    /// match this package's established `Synchronizer.Blocking` usage
    /// (compare `Kernel.Thread.Gate.open()`).
    ///
    /// ## Intended Use
    ///
    /// A private drain counter owned by exactly one `Pool`; not a
    /// general-purpose counting primitive.
    final class InFlight: @unsafe @unchecked Sendable {
        private let sync = Synchronizer.Blocking<1>()
        private var count = 0

        init() {}
    }
}

extension Kernel.Thread.Pool.InFlight {
    /// Marks the start of a `run` call.
    ///
    /// Must be paired with exactly one `leave()`, regardless of how the
    /// call eventually exits (admitted and completed, or rejected).
    func enter() {
        sync.lock()
        count += 1
        sync.unlock()
    }

    /// Marks the completion of a `run` call.
    func leave() {
        sync.lock()
        count -= 1
        precondition(count >= 0, "Kernel.Thread.Pool.InFlight: leave() outnumbers enter()")
        let isIdle = count == 0
        sync.unlock()
        if isIdle {
            sync.broadcast(condition: 0)
        }
    }

    /// Blocks the calling thread until every `run` call that has already
    /// entered has left.
    ///
    /// - Precondition: New admissions must already be rejected (e.g. via
    ///   `admission.shutdown()`) before calling this — otherwise the count
    ///   may never reach zero.
    func waitUntilIdle() {
        sync.lock()
        defer { sync.unlock() }
        while count != 0 {
            sync.wait(condition: 0)
        }
    }
}
