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
    /// Operational metrics for a semaphore.
    public struct Metrics: Sendable, Equatable {
        /// Total number of successful permit acquisitions.
        public var acquisitions: UInt64 = 0

        /// Total number of permit releases.
        public var releases: UInt64 = 0

        /// Number of acquisition attempts rejected due to shutdown.
        public var rejected: UInt64 = 0

        /// Number of acquisition attempts that timed out.
        public var timeouts: UInt64 = 0

        /// Number of acquisition attempts cancelled.
        public var cancellations: UInt64 = 0

        /// Current number of permits held by callers.
        public var outstanding: Int = 0

        /// Current number of permits available for acquisition.
        public var available: Int = 0

        /// Current number of threads waiting to acquire a permit.
        public var waiters: Int = 0

        /// Peak number of permits ever held simultaneously.
        public var peak: Int = 0
    }
}
