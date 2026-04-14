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

internal import Synchronization

extension Kernel.Thread.Semaphore {
    /// A thread-safe cancellation token for semaphore operations.
    ///
    /// ## Usage
    /// ```swift
    /// let token = Kernel.Thread.Semaphore.Cancellation()
    ///
    /// // Pass to a cancellable acquisition
    /// let result = try semaphore.run.cancellable(token) { work() }
    ///
    /// // Cancel from another thread
    /// token.cancel()
    /// ```
    public struct Cancellation: Sendable {
        @usableFromInline
        let storage: Storage

        /// Creates a new cancellation token in the non-cancelled state.
        public init() {
            self.storage = Storage()
        }
    }
}

extension Kernel.Thread.Semaphore.Cancellation {
    /// Whether this token has been cancelled.
    public var isCancelled: Bool {
        storage.flag.load(ordering: .acquiring)
    }

    /// Cancels this token, causing pending cancellable operations to throw.
    public func cancel() {
        storage.flag.store(true, ordering: .releasing)
    }
}
