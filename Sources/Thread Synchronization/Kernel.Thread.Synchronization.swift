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
    /// Mutex + N condition variable(s) wrapper.
    ///
    /// Parameterized by condition count for compile-time safety:
    /// - `Synchronization<1>` - single condition (executor job queue)
    /// - `Synchronization<2>` - dual conditions (worker/deadline separation)
    ///
    /// Uses `InlineArray` for zero-allocation fixed-size storage.
    ///
    /// ## Safety Invariant
    ///
    /// This type is `Sendable` by virtue of internal synchronization: every
    /// access to the mutex-protected condition variables and waiter counts
    /// is serialized by `Kernel.Thread.Mutex`. The caller MUST route every
    /// access to protected state through `lock()` / `unlock()` / `withLock(_:)`,
    /// and MUST NOT read or mutate `conditions` or `waiterCounts` outside the
    /// lock. The `@unsafe` annotation makes this assertion explicit at the
    /// conformance site — callers inherit the obligation to respect the lock.
    ///
    /// ## Intended Use
    ///
    /// Coordinating producers and consumers under a single mutex with one
    /// or two associated condition variables. Typical consumers:
    /// - Serial executor job queues (`Synchronization<1>`).
    /// - Worker / deadline separation in the stealing executor
    ///   (`Synchronization<2>`).
    /// - Any small, bounded producer/consumer signalling where atomic-only
    ///   primitives are insufficient and a condition variable wait is needed.
    ///
    /// Cross-isolation transfer is sound because every accessor serializes
    /// through the mutex — moving the reference between threads does not
    /// introduce a race that the mutex does not already mediate.
    ///
    /// ## Non-Goals
    ///
    /// - Not a lock-free primitive. Every operation pays for mutex acquisition.
    ///   For high-contention hot paths where atomic primitives suffice, use
    ///   those instead.
    /// - Not a general "thread-safe object." This conformance does not make
    ///   arbitrary concurrent access safe. Access to the protected condition
    ///   variables and waiter counts MUST go through the documented
    ///   `lock()` / `withLock(_:)` API; touching the stored state outside
    ///   the lock is undefined behaviour.
    /// - Not a replacement for a proper actor. When the coordination is
    ///   naturally expressible via Swift concurrency, prefer an actor;
    ///   `Synchronization` exists for the thread-level layer underneath.
    ///
    /// ## Usage
    /// ```swift
    /// let sync = Kernel.Thread.Synchronization<2>()
    ///
    /// sync.lock()
    /// defer { sync.unlock() }
    ///
    /// // Wait on condition 0 (worker)
    /// sync.wait(condition: 0)
    ///
    /// // Signal condition 1 (deadline)
    /// sync.signal(condition: 1)
    /// ```
    public final class Synchronization<let N: Int>: @unsafe @unchecked Sendable {
        private let mutex = Kernel.Thread.Mutex()
        private var conditions: InlineArray<N, Kernel.Thread.Condition>
        private var waiterCounts: InlineArray<N, Int>

        /// Creates synchronization with N condition variables.
        ///
        /// - Precondition: N must be at least 1.
        public init() {
            precondition(N >= 1, "Synchronization requires at least 1 condition variable")
            self.conditions = InlineArray { _ in Kernel.Thread.Condition() }
            self.waiterCounts = InlineArray { _ in 0 }
        }
    }
}

// MARK: - Lock Operations

extension Kernel.Thread.Synchronization {
    /// Acquire the lock.
    public func lock() {
        mutex.lock()
    }

    /// Release the lock.
    public func unlock() {
        mutex.unlock()
    }

    /// Execute a closure while holding the lock.
    public func withLock<T, E: Swift.Error>(_ body: () throws(E) -> T) throws(E) -> T {
        try mutex.withLock(body)
    }
}

// MARK: - Condition Variable Operations

extension Kernel.Thread.Synchronization {
    /// Wait on the specified condition variable.
    ///
    /// Must be called while holding the lock.
    /// The lock is released while waiting and reacquired before returning.
    ///
    /// - Parameter condition: Index of condition variable (0..<N).
    /// - Precondition: Index must be in range 0..<N.
    public func wait(condition index: Int = 0) {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        conditions[index].wait(mutex: mutex)
    }

    /// Wait on the specified condition variable with timeout.
    ///
    /// Must be called while holding the lock.
    /// The lock is released while waiting and reacquired before returning.
    ///
    /// - Parameters:
    ///   - condition: Index of condition variable (0..<N).
    ///   - nanoseconds: Timeout in nanoseconds. Values exceeding Int64.max are clamped.
    /// - Returns: `true` if signaled, `false` if timed out.
    /// - Precondition: Index must be in range 0..<N.
    public func wait(condition index: Int = 0, timeout nanoseconds: UInt64) -> Bool {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        let clampedNanos = Int64(clamping: nanoseconds)
        return conditions[index].wait(mutex: mutex, timeout: .nanoseconds(clampedNanos))
    }

    /// Wait on the specified condition variable with Duration timeout.
    ///
    /// Must be called while holding the lock.
    /// The lock is released while waiting and reacquired before returning.
    ///
    /// - Parameters:
    ///   - condition: Index of condition variable (0..<N).
    ///   - timeout: Maximum duration to wait.
    /// - Returns: `true` if signaled, `false` if timed out.
    /// - Precondition: Index must be in range 0..<N.
    public func wait(condition index: Int = 0, timeout: Duration) -> Bool {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        return conditions[index].wait(mutex: mutex, timeout: timeout)
    }

    /// Signal one thread waiting on the specified condition variable.
    ///
    /// - Parameter condition: Index of condition variable (0..<N).
    /// - Precondition: Index must be in range 0..<N.
    public func signal(condition index: Int = 0) {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        conditions[index].signal()
    }

    /// Signal all threads waiting on the specified condition variable.
    ///
    /// - Parameter condition: Index of condition variable (0..<N).
    /// - Precondition: Index must be in range 0..<N.
    public func broadcast(condition index: Int = 0) {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        conditions[index].broadcast()
    }

    // WORKAROUND: Compound name — needs Property<Tag, Base> accessor pattern
    // WHY: Property-primitives not yet a dependency of swift-kernel
    // WHEN TO REMOVE: When property-primitives is adopted; refactor to wait.tracked(), signal.conditional(), broadcast.conditional(), broadcast.all()
    // TRACKING: swift-kernel-deep-audit [API-NAME-002]
    /// Signal all threads waiting on all condition variables.
    public func broadcastAll() {
        for i in 0..<N {
            conditions[i].broadcast()
        }
    }
}

// MARK: - Waiter Tracking Operations

extension Kernel.Thread.Synchronization {
    /// Returns the current waiter count for the specified condition.
    ///
    /// Must be called while holding the lock.
    ///
    /// - Note: This value is only semantically valid if all waits on this condition
    ///   use `waitTracked` during the period in which you rely on this count.
    ///
    /// - Parameter condition: Index of condition variable (0..<N).
    /// - Returns: Number of threads currently waiting on this condition.
    /// - Precondition: Index must be in range 0..<N.
    public func waiters(condition: Int = 0) -> Int {
        precondition(condition >= 0 && condition < N, "Condition index \(condition) out of bounds (0..<\(N))")
        return waiterCounts[condition]
    }

    // WORKAROUND: Compound name — needs Property<Tag, Base> accessor pattern
    // WHY: Property-primitives not yet a dependency of swift-kernel
    // WHEN TO REMOVE: When property-primitives is adopted; refactor to wait.tracked(), signal.conditional(), broadcast.conditional(), broadcast.all()
    // TRACKING: swift-kernel-deep-audit [API-NAME-002]
    /// Wait on the specified condition variable while tracking waiter count.
    ///
    /// Must be called while holding the lock.
    /// The lock is released while waiting and reacquired before returning.
    /// Waiter count is incremented before waiting and decremented after.
    ///
    /// - Note: For correct waiter counts, all waits on this condition should use
    ///   `waitTracked` rather than mixing with `wait`.
    ///
    /// - Parameter condition: Index of condition variable (0..<N).
    /// - Precondition: Index must be in range 0..<N.
    public func waitTracked(condition index: Int = 0) {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        waiterCounts[index] += 1
        defer {
            waiterCounts[index] -= 1
            assert(waiterCounts[index] >= 0, "Waiter count underflow")
        }
        conditions[index].wait(mutex: mutex)
    }

    // WORKAROUND: Compound name — needs Property<Tag, Base> accessor pattern
    // WHY: Property-primitives not yet a dependency of swift-kernel
    // WHEN TO REMOVE: When property-primitives is adopted; refactor to wait.tracked(), signal.conditional(), broadcast.conditional(), broadcast.all()
    // TRACKING: swift-kernel-deep-audit [API-NAME-002]
    /// Wait on the specified condition variable with timeout while tracking waiter count.
    ///
    /// Must be called while holding the lock.
    /// The lock is released while waiting and reacquired before returning.
    /// Waiter count is incremented before waiting and decremented after.
    ///
    /// - Note: For correct waiter counts, all waits on this condition should use
    ///   `waitTracked` rather than mixing with `wait`.
    ///
    /// - Parameters:
    ///   - condition: Index of condition variable (0..<N).
    ///   - timeout: Maximum duration to wait.
    /// - Returns: `true` if signaled, `false` if timed out.
    /// - Precondition: Index must be in range 0..<N.
    public func waitTracked(condition index: Int = 0, timeout: Duration) -> Bool {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        waiterCounts[index] += 1
        defer {
            waiterCounts[index] -= 1
            assert(waiterCounts[index] >= 0, "Waiter count underflow")
        }
        return conditions[index].wait(mutex: mutex, timeout: timeout)
    }

    // WORKAROUND: Compound name — needs Property<Tag, Base> accessor pattern
    // WHY: Property-primitives not yet a dependency of swift-kernel
    // WHEN TO REMOVE: When property-primitives is adopted; refactor to wait.tracked(), signal.conditional(), broadcast.conditional(), broadcast.all()
    // TRACKING: swift-kernel-deep-audit [API-NAME-002]
    /// Signal one thread if any are waiting on the specified condition.
    ///
    /// Skips the signal syscall if no waiters exist.
    ///
    /// - Parameter condition: Index of condition variable (0..<N).
    /// - Returns: `true` if signal was sent (waiters existed), `false` if skipped.
    /// - Precondition: Index must be in range 0..<N.
    public func signalIfWaiters(condition index: Int = 0) -> Bool {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        guard waiterCounts[index] > 0 else { return false }
        conditions[index].signal()
        return true
    }

    // WORKAROUND: Compound name — needs Property<Tag, Base> accessor pattern
    // WHY: Property-primitives not yet a dependency of swift-kernel
    // WHEN TO REMOVE: When property-primitives is adopted; refactor to wait.tracked(), signal.conditional(), broadcast.conditional(), broadcast.all()
    // TRACKING: swift-kernel-deep-audit [API-NAME-002]
    /// Broadcast to all threads if any are waiting on the specified condition.
    ///
    /// Skips the broadcast syscall if no waiters exist.
    ///
    /// - Parameter condition: Index of condition variable (0..<N).
    /// - Returns: `true` if broadcast was sent (waiters existed), `false` if skipped.
    /// - Precondition: Index must be in range 0..<N.
    public func broadcastIfWaiters(condition index: Int = 0) -> Bool {
        precondition(index >= 0 && index < N, "Condition index \(index) out of bounds (0..<\(N))")
        guard waiterCounts[index] > 0 else { return false }
        conditions[index].broadcast()
        return true
    }
}
