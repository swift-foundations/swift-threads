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
    /// A thread-blocking counting semaphore.
    ///
    /// Semaphore limits concurrent access to a resource by maintaining a count
    /// of available permits. Threads acquire a permit before accessing the
    /// resource and release it when done. When no permits are available,
    /// acquiring threads block until a permit is released.
    ///
    /// ## Safety Invariant
    ///
    /// This type is `Sendable` by virtue of internal synchronization: the entire
    /// `_state` struct (permit counts, waiter counts, metrics, lifecycle) is
    /// protected by `Synchronizer.Blocking<2>` -- a single mutex paired with two
    /// condition variables (`available` and `shutdown`). Every path -- acquire,
    /// release, shutdown, wait, metrics snapshot -- serializes on the mutex and
    /// signals/broadcasts the appropriate condition under the lock. The caller
    /// MUST route every access through the documented public API; touching
    /// `_state` outside the lock is undefined behaviour.
    ///
    /// ## Intended Use
    ///
    /// - Bounding concurrency over a shared resource at the kernel-thread
    ///   layer (e.g., "no more than N in-flight requests", "at most K open
    ///   file handles").
    /// - Graceful shutdown with outstanding-permit draining via
    ///   `shutdown.wait()`.
    /// - Metrics-bearing coordination point where acquire/release/reject/
    ///   timeout counters are observable.
    ///
    /// ## Non-Goals
    ///
    /// - Not an actor. Semaphore does not suspend Swift concurrency tasks;
    ///   it blocks threads. For async permit acquisition use an actor or a
    ///   Swift-concurrency-native primitive.
    /// - Not a lock-free semaphore. Every acquire/release pays for mutex
    ///   acquisition; the dual-condvar layout optimizes for condvar fan-out,
    ///   not uncontended throughput.
    /// - Not reentrant. A thread holding a permit and calling `acquire`
    ///   again does not recursively succeed; it blocks.
    ///
    /// ## Usage
    /// ```swift
    /// let semaphore = Kernel.Thread.Semaphore(capacity: 3)
    ///
    /// // Scoped acquire/release
    /// let result = try semaphore.run { expensiveWork() }
    ///
    /// // With timeout
    /// let result = try semaphore.run.timeout(.seconds(5)) { work() }
    ///
    /// // Graceful shutdown
    /// semaphore.shutdown.wait()
    /// ```
    public final class Semaphore: @unsafe @unchecked Sendable {
        @usableFromInline
        let sync: Synchronizer.Blocking<2>

        @usableFromInline
        var _state: State

        /// The total number of permits managed by this semaphore.
        public let capacity: Int

        /// Creates a semaphore with the given capacity.
        ///
        /// - Parameter capacity: The number of concurrent permits.
        /// - Precondition: Capacity must be at least 1.
        public init(capacity: Int) {
            precondition(capacity >= 1, "Semaphore capacity must be at least 1")
            self.capacity = capacity
            self.sync = Synchronizer.Blocking<2>()
            self._state = State(capacity: capacity)
        }
    }
}

// MARK: - Acquire

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _acquire() throws(Error) {
        sync.lock()
        defer { sync.unlock() }

        while true {
            if _state.lifecycle != .open {
                _state.metrics.rejected += 1
                throw .shutdown
            }
            if _state.available > 0 {
                _state.available -= 1
                _state.outstanding += 1
                _state.metrics.acquisitions += 1
                _state.metrics.outstanding = _state.outstanding
                _state.metrics.available = _state.available
                if _state.outstanding > _state.metrics.peak {
                    _state.metrics.peak = _state.outstanding
                }
                return
            }
            _state.waiters += 1
            sync.wait(condition: Condition.available.rawValue)
            _state.waiters -= 1
            precondition(_state.waiters >= 0, "Waiter count underflow")
        }
    }

    @usableFromInline
    func _acquire(timeout duration: Duration) throws(Error) -> Bool {
        sync.lock()
        defer { sync.unlock() }

        let deadline = Clock.Continuous.now.advanced(by: duration)

        while true {
            if _state.lifecycle != .open {
                _state.metrics.rejected += 1
                throw .shutdown
            }
            if _state.available > 0 {
                _state.available -= 1
                _state.outstanding += 1
                _state.metrics.acquisitions += 1
                _state.metrics.outstanding = _state.outstanding
                _state.metrics.available = _state.available
                if _state.outstanding > _state.metrics.peak {
                    _state.metrics.peak = _state.outstanding
                }
                return true
            }
            let remaining = deadline - Clock.Continuous.now
            if remaining <= .zero {
                _state.metrics.timeouts += 1
                return false
            }

            _state.waiters += 1
            _ = sync.wait(condition: Condition.available.rawValue, timeout: remaining)
            _state.waiters -= 1
            precondition(_state.waiters >= 0, "Waiter count underflow")
        }
    }

    @usableFromInline
    func _acquire(cancellation token: Cancellation, poll interval: Duration) throws(Error) {
        sync.lock()
        defer { sync.unlock() }

        while true {
            if _state.lifecycle != .open {
                _state.metrics.rejected += 1
                throw .shutdown
            }
            if token.isCancelled {
                _state.metrics.cancellations += 1
                throw .cancelled
            }
            if _state.available > 0 {
                _state.available -= 1
                _state.outstanding += 1
                _state.metrics.acquisitions += 1
                _state.metrics.outstanding = _state.outstanding
                _state.metrics.available = _state.available
                if _state.outstanding > _state.metrics.peak {
                    _state.metrics.peak = _state.outstanding
                }
                return
            }

            _state.waiters += 1
            _ = sync.wait(condition: Condition.available.rawValue, timeout: interval)
            _state.waiters -= 1
            precondition(_state.waiters >= 0, "Waiter count underflow")
        }
    }
}

// MARK: - Release

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _release() {
        let effect: Effect = sync.synchronize {
            _state.outstanding -= 1
            _state.available += 1
            _state.metrics.releases += 1
            _state.metrics.outstanding = _state.outstanding
            _state.metrics.available = _state.available

            if _state.lifecycle == .open {
                return .signal(.available)
            } else {
                return _close()
            }
        }
        perform(effect)
    }
}

// MARK: - Shutdown

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _shutdown() {
        let effect: Effect = sync.synchronize {
            guard _state.lifecycle == .open else {
                return .none
            }
            _state.lifecycle = .closing

            if _state.outstanding == 0 {
                _state.lifecycle = .closed
                return .broadcast(.shutdown)
            } else {
                return .broadcast(.available)
            }
        }
        perform(effect)
    }

    @usableFromInline
    func _wait() {
        sync.lock()
        defer { sync.unlock() }

        if _state.lifecycle == .open {
            sync.unlock()
            _shutdown()
            sync.lock()
        }

        while _state.lifecycle != .closed {
            sync.wait(condition: Condition.shutdown.rawValue)
        }
    }
}

// MARK: - Completion Check

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _close() -> Effect {
        guard _state.lifecycle == .closing,
              _state.outstanding == 0 else {
            return .none
        }
        _state.lifecycle = .closed
        return .broadcast(.shutdown)
    }
}

// MARK: - Single Funnel

extension Kernel.Thread.Semaphore {
    @inline(always)
    func perform(_ effect: Effect) {
        switch effect {
        case .none:
            return
        case .signal(let condition):
            sync.signal(condition: condition.rawValue)
        case .broadcast(let condition):
            sync.broadcast(condition: condition.rawValue)
        }
    }
}

// MARK: - Metrics

extension Kernel.Thread.Semaphore {
    /// A snapshot of the semaphore's operational metrics.
    public var metrics: Metrics {
        sync.lock()
        defer { sync.unlock() }
        var m = _state.metrics
        m.waiters = _state.waiters
        return m
    }
}
