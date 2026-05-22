// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-kernel open source project
//
// Copyright (c) 2024-2025 Coen ten Thije Boonkkamp and the swift-kernel project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

extension Kernel.Thread {
    /// A barrier for synchronizing multiple threads.
    ///
    /// All threads wait at `arrive()` until the target count arrives,
    /// then all proceed together.
    ///
    /// ## Safety Invariant
    ///
    /// This type is `Sendable` by virtue of internal synchronization: every access
    /// to `_arrived`, `target`, `released`, and the shared condition variable is
    /// serialized by `Synchronizer.Blocking<1>` (a single-condition
    /// mutex+condvar wrapper). The caller MUST route every access through the
    /// provided `arrive(timeout:)` / `arrived` API; reaching into the stored
    /// state outside the mutex is undefined behaviour. The `@unsafe` annotation
    /// makes this assertion explicit at the conformance site.
    ///
    /// ## Intended Use
    ///
    /// - Rendezvous coordination for a fixed team of threads (parallel
    ///   benchmarks, phased computation, simulation steps).
    /// - Cross-isolation transfer where producers and consumers need one-shot
    ///   "everyone arrived" synchronization before proceeding together.
    /// - Replacement for ad-hoc atomic counters + condvar plumbing at the
    ///   kernel-thread layer.
    ///
    /// ## Non-Goals
    ///
    /// - Not a reusable barrier phaser. Once the target count is reached and
    ///   `released` is set, the barrier stays released. Construct a new
    ///   `Barrier` for each generation.
    /// - Not lock-free. Every `arrive` pays for mutex acquisition; unsuitable
    ///   for hot paths where atomic primitives suffice.
    /// - Not a substitute for Swift `Task` group semantics. For async
    ///   coordination use the structured-concurrency primitives; `Barrier`
    ///   exists at the thread layer underneath.
    ///
    /// ## Usage
    /// ```swift
    /// let barrier = Kernel.Thread.Barrier(count: 3)
    ///
    /// // Thread 1, 2, 3
    /// let success = barrier.arrive(timeout: .seconds(5))
    /// // All threads released simultaneously when 3rd arrives
    /// ```
    public final class Barrier: @unsafe @unchecked Sendable {
        private var _arrived: Int = 0
        private let target: Int
        private var released: Bool = false
        private let sync = Synchronizer.Blocking<1>()

        /// Creates a barrier with the given target count.
        ///
        /// - Parameter count: Number of threads that must arrive before release.
        /// - Precondition: Count must be at least 1.
        public init(count: Int) {
            precondition(count >= 1, "Barrier count must be at least 1")
            self.target = count
        }
    }
}

extension Kernel.Thread.Barrier {
    /// Wait until all threads arrive or timeout expires.
    ///
    /// Blocks the current thread until either:
    /// - All threads have arrived (returns `true`)
    /// - The timeout expires (returns `false`)
    ///
    /// - Parameter timeout: Maximum time to wait. Defaults to 5 seconds.
    /// - Returns: `true` if all threads arrived, `false` on timeout.
    public func arrive(timeout: Duration = .seconds(5)) -> Bool {
        sync.lock()
        defer { sync.unlock() }

        _arrived += 1

        if _arrived >= target {
            released = true
            sync.broadcast(condition: 0)
            return true
        }

        while !released {
            if !sync.wait(condition: 0, timeout: timeout) {
                return false
            }
        }
        return true
    }

    /// Current count of threads that have arrived.
    public var arrived: Int {
        sync.synchronize { _arrived }
    }
}
