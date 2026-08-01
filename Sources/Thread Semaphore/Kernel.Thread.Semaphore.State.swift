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

extension Kernel.Thread.Semaphore {
    @usableFromInline
    struct State: Sendable {
        var available: Int
        var outstanding: Int
        var waiters: Int
        var lifecycle: Lifecycle
        var metrics: Metrics

        init(capacity: Int) {
            self.available = capacity
            self.outstanding = 0
            self.waiters = 0
            self.lifecycle = .open
            self.metrics = Metrics()
            self.metrics.available = capacity
        }
    }
}
