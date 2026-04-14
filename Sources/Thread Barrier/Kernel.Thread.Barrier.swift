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
    /// ## Usage
    /// ```swift
    /// let barrier = Kernel.Thread.Barrier(count: 3)
    ///
    /// // Thread 1, 2, 3
    /// let success = barrier.arrive(timeout: .seconds(5))
    /// // All threads released simultaneously when 3rd arrives
    /// ```
    ///
    /// ## Thread Safety
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    public final class Barrier: @unchecked Sendable {
        private var _arrived: Int = 0
        private let target: Int
        private var released: Bool = false
        private let sync = SingleSync()

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
        sync.withLock { _arrived }
    }
}
