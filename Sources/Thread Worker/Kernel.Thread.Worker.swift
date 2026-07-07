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

extension Kernel.Thread {
    /// A managed thread lifecycle abstraction.
    ///
    /// ## Purpose
    /// `Worker` provides a reusable building block for managed thread ownership:
    /// - Exactly-once start (factory construction)
    /// - Stop request signaling
    /// - Exactly-once join (via consuming `join()`)
    ///
    /// ## Layer Boundary
    /// This is a **convenience** - it knows nothing about:
    /// - Job queues
    /// - Deadlines or backpressure
    /// - Lane policies
    /// - Wakeup mechanisms (polling only - no condition variables)
    ///
    /// Higher-level constructs can compose this and add their own scheduling semantics.
    ///
    /// ## Lifecycle Protocol
    /// - `stop()` is thread-safe and may be called from any thread.
    /// - `join()` is a consuming terminal operation and must not race with
    ///   other operations on the same Worker value.
    /// - The value is single-owner by construction (`~Copyable`).
    ///
    /// ## Usage
    /// ```swift
    /// var worker = try Kernel.Thread.Worker.start { token in
    ///     while !token.shouldStop {
    ///         // do work
    ///     }
    /// }
    ///
    /// // Later, signal stop and join
    /// worker.stop()
    /// consume worker.join()
    /// ```
    public struct Worker: ~Copyable, Sendable {
        /// The thread handle, consumed exactly once on join.
        private var handle: Handle

        /// The stop token shared with the running thread.
        private let token: Token

        /// Creates a worker (private - use factory `start`).
        private init(handle: consuming Handle, token: Token) {
            self.handle = handle
            self.token = token
        }
    }
}

// MARK: - Factory Start

extension Kernel.Thread.Worker {
    /// Starts a managed worker thread.
    ///
    /// The body receives a `Token` to observe stop requests. When `token.shouldStop`
    /// becomes true, the body should exit promptly.
    ///
    /// ## Lifecycle Guarantees
    /// - The thread is started before this function returns
    /// - The body is invoked exactly once
    /// - On failure, resources are cleaned up (no leaks)
    ///
    /// ## Example
    /// ```swift
    /// var worker = try Kernel.Thread.Worker.start { token in
    ///     while !token.shouldStop {
    ///         processNextItem()
    ///     }
    /// }
    /// worker.stop()
    /// consume worker.join()
    /// ```
    ///
    /// - Parameter body: Work to run on the thread. Receives a stop token.
    /// - Returns: A started worker with an owned handle.
    /// - Throws: `Kernel.Thread.Error` if thread creation fails.
    public static func start(
        _ body: @escaping @Sendable (Token) -> Void
    ) throws(Kernel.Thread.Error) -> Self {
        let token = Token()

        let handle = try Kernel.Thread.spawn {
            body(token)
        }

        return Self(handle: handle, token: token)
    }
}

// MARK: - Lifecycle Operations

extension Kernel.Thread.Worker {
    /// Request the worker to stop.
    ///
    /// Sets the stop flag that the worker body observes via `token.shouldStop`.
    /// This does not forcibly terminate the thread - the body must cooperate
    /// by checking the token and exiting.
    ///
    /// This is idempotent - calling multiple times is safe.
    public func stop() {
        token.requestStop()
    }

    /// Check if stop has been requested.
    public var isStopping: Bool {
        token.shouldStop
    }

    /// Wait for the thread to complete and release resources.
    ///
    /// This is a consuming operation - the worker cannot be used after calling `join()`.
    /// The thread must have exited (typically after observing `token.shouldStop`).
    ///
    /// - Precondition: Must NOT be called from the worker's own thread (deadlock).
    /// - Note: Must be called exactly once. The `~Copyable` constraint enforces this.
    public consuming func join() {
        precondition(
            handle.isCurrent == false,
            "Kernel.Thread.Worker.join() called from the worker's own thread - this would deadlock"
        )
        handle.join()
    }
}
