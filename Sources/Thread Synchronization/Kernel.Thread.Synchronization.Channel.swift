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

// MARK: - Convenience for Dual Sync

extension Kernel.Thread.Synchronization where N == 2 {
    /// Accessor for worker condition (index 0).
    public var worker: Channel {
        Channel(sync: self, index: 0)
    }

    /// Accessor for deadline condition (index 1).
    public var deadline: Channel {
        Channel(sync: self, index: 1)
    }

    /// Accessor for a specific condition variable.
    public struct Channel: Sendable {
        private let sync: Kernel.Thread.Synchronization<2>
        private let index: Int

        init(sync: Kernel.Thread.Synchronization<2>, index: Int) {
            self.sync = sync
            self.index = index
        }
    }
}

extension Kernel.Thread.Synchronization.Channel {
    /// Wait on this condition.
    public func wait() {
        sync.wait(condition: index)
    }

    /// Wait on this condition with timeout.
    public func wait(timeout nanoseconds: UInt64) -> Bool {
        sync.wait(condition: index, timeout: nanoseconds)
    }

    /// Wait on this condition with Duration timeout.
    public func wait(timeout: Duration) -> Bool {
        sync.wait(condition: index, timeout: timeout)
    }

    /// Signal one waiter on this condition.
    public func signal() {
        sync.signal(condition: index)
    }

    /// Broadcast to all waiters on this condition.
    public func broadcast() {
        sync.broadcast(condition: index)
    }

    // MARK: - Waiter Tracking

    /// Current waiter count for this condition.
    ///
    /// Only valid if all waits use `waitTracked`.
    public var waiters: Int {
        sync.waiters(condition: index)
    }

    /// Wait on this condition while tracking waiter count.
    public func waitTracked() {
        sync.waitTracked(condition: index)
    }

    /// Wait on this condition with timeout while tracking waiter count.
    public func waitTracked(timeout: Duration) -> Bool {
        sync.waitTracked(condition: index, timeout: timeout)
    }

    /// Signal one waiter if any exist on this condition.
    @discardableResult
    public func signalIfWaiters() -> Bool {
        sync.signalIfWaiters(condition: index)
    }

    /// Broadcast if any waiters exist on this condition.
    @discardableResult
    public func broadcastIfWaiters() -> Bool {
        sync.broadcastIfWaiters(condition: index)
    }
}
