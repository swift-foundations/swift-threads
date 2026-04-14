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
    /// Errors that can occur during semaphore operations.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The semaphore is shutting down or has shut down.
        case shutdown

        /// The operation was cancelled.
        case cancelled

        /// The operation timed out waiting for a permit.
        case timeout
    }
}
