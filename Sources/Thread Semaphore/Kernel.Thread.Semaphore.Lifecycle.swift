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
    /// Three-state lifecycle for graceful shutdown.
    @usableFromInline
    enum Lifecycle: Sendable, Equatable {
        /// Normal operation — permits may be acquired.
        case open

        /// Draining outstanding permits — no new acquisitions.
        case closing

        /// Fully shut down.
        case closed
    }
}
