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

import Synchronization

extension Kernel.Thread.Worker {
    /// Stop signaling token passed to the worker body.
    ///
    /// The running thread checks `shouldStop` to know when to exit gracefully.
    /// The owner calls `stop()` on the Worker to signal shutdown.
    ///
    /// ## No Wakeup Mechanism
    /// This is a polling-based token only. There is no condition variable or
    /// event to wake the thread. If you need wakeup semantics, use a higher-level
    /// construct that adds synchronization primitives.
    ///
    /// ## Thread Safety
    /// Uses `Atomic<Bool>` for lock-free signaling. The token is safe to access
    /// from any thread.
    public final class Token: Sendable {
        private let stopped: Atomic<Bool>

        init() {
            self.stopped = Atomic(false)
        }
    }
}

extension Kernel.Thread.Worker.Token {
    /// Check if stop has been requested.
    ///
    /// The worker body should poll this regularly to exit gracefully.
    public var shouldStop: Bool {
        stopped.load(ordering: .acquiring)
    }

    /// Request the worker to stop (internal - use Worker.stop()).
    func requestStop() {
        stopped.store(true, ordering: .releasing)
    }
}
