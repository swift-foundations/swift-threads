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
    /// A one-shot blocking synchronization primitive.
    ///
    /// Gate provides a simple rendezvous point where threads block until
    /// the gate is opened. Once opened, the gate stays open permanently
    /// and all current and future waiters proceed immediately.
    ///
    /// ## Pattern
    /// - Waiters call `wait()` (blocks until gate opens)
    /// - Signaler calls `open()` (releases all waiters)
    ///
    /// ## One-Shot Semantics
    /// A gate can only be opened once. After `open()`, the gate remains
    /// open permanently. This is intentional - for reusable barriers,
    /// use `Kernel.Thread.Barrier` instead.
    ///
    /// ## Usage
    /// ```swift
    /// let ready = Kernel.Thread.Gate()
    ///
    /// // Thread 1 (waiter)
    /// ready.wait()  // Blocks until opened
    /// // ... proceed after gate opens
    ///
    /// // Thread 2 (signaler)
    /// ready.open()  // Releases all waiters
    /// ```
    ///
    /// ## Thread Safety
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    public final class Gate: @unchecked Sendable {
        private var _isOpen: Bool = false
        private let sync = SingleSync()

        /// Creates a new closed gate.
        public init() {}
    }
}

extension Kernel.Thread.Gate {
    /// Opens the gate, releasing all waiting threads.
    ///
    /// After this call:
    /// - All currently waiting threads resume
    /// - All future `wait()` calls return immediately
    ///
    /// Opening an already-open gate is a no-op.
    public func open() {
        let didOpen = sync.withLock {
            guard !_isOpen else { return false }
            _isOpen = true
            return true
        }
        if didOpen {
            sync.broadcast(condition: 0)
        }
    }

    /// Blocks until the gate is opened.
    ///
    /// If the gate is already open, returns immediately.
    /// Otherwise, blocks until another thread calls `open()`.
    public func wait() {
        sync.lock()
        defer { sync.unlock() }
        while !_isOpen {
            sync.wait(condition: 0)
        }
    }

    /// Blocks until the gate is opened or timeout expires.
    ///
    /// - Parameter timeout: Maximum duration to wait.
    /// - Returns: `true` if gate was opened, `false` if timed out.
    public func wait(timeout: Duration) -> Bool {
        sync.lock()
        defer { sync.unlock() }
        while !_isOpen {
            if !sync.wait(condition: 0, timeout: timeout) {
                return _isOpen
            }
        }
        return true
    }

    /// Whether the gate is currently open.
    ///
    /// This is a non-blocking check.
    public var isOpen: Bool {
        sync.withLock { _isOpen }
    }
}
