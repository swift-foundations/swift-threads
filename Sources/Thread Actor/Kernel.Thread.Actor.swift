// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-threads open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-threads
// project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Executors

extension Kernel.Thread {

    /// A Swift `actor` pinned to a single `Kernel.Thread.Executor`.
    ///
    /// ``Actor`` is the canonical primitive for the pinned-thread,
    /// shared-executor (TCA26) pattern. An instance owns one
    /// ``Kernel/Thread/Executor``; the actor's isolation domain is
    /// precisely that executor's pinned OS thread. Every isolated method
    /// call on the actor — including methods added by extensions
    /// downstream — runs on that single thread, serialised by actor
    /// isolation.
    ///
    /// ## Design
    ///
    /// The actor deliberately ships with no operations. Domain packages
    /// (for example swift-io for basic fd byte ops, swift-file-system
    /// for file operations, swift-sockets for socket operations) add
    /// their syscall methods via `extension Kernel.Thread.Actor { ... }`.
    /// Because Swift's extension visibility is module-scoped, an
    /// extension added by one domain only appears to consumers that
    /// import that domain — there is no global method pile-on.
    ///
    /// ## Shared-executor (TCA26) co-location
    ///
    /// Consumers that want to co-locate their own actor with this
    /// actor's pinned thread forward its `unownedExecutor`:
    ///
    /// ```swift
    /// actor Worker {
    ///     let io: Kernel.Thread.Actor
    ///
    ///     nonisolated var unownedExecutor: UnownedSerialExecutor {
    ///         io.unownedExecutor
    ///     }
    /// }
    /// ```
    ///
    /// With this forwarding, calls from `Worker` to `io`'s isolated
    /// methods incur no executor hop — both actors resolve to the same
    /// pinned thread.
    ///
    /// ## Isolation contract
    ///
    /// **One actor instance = one thread = one isolation domain.** All
    /// extension methods on a single ``Actor`` instance run serialised
    /// on its pinned thread. If different workloads require distinct
    /// thread residences, create distinct ``Actor`` instances with
    /// distinct `Kernel.Thread.Executor` instances.
    ///
    /// Two ``Actor`` instances sharing one `Kernel.Thread.Executor`
    /// land on the same OS thread by virtue of the executor, but remain
    /// separate Swift isolation domains. Prefer one actor per pinned
    /// thread unless you have a specific reason to share.
    ///
    /// ## Relation to ``Kernel/Thread/Pool``
    ///
    /// ``Kernel/Thread/Pool`` is the admission-gated, task-hop
    /// dispatch primitive — use ``Pool/run(_:_:)`` when the calling
    /// actor is *not* pinned to the worker thread and throughput benefits
    /// from admission throttling. ``Actor`` is the pinned-actor
    /// dispatch primitive — use it when a consumer actor wants to share
    /// the worker's thread (zero-hop method calls) and admission
    /// throttling is unnecessary.
    ///
    /// Choose by asking: "Does the caller want to co-locate on the
    /// worker thread?" If yes → ``Actor``. If no → ``Pool``.
    public actor Actor {

        /// The pinned executor this actor runs on.
        public let executor: Kernel.Thread.Executor

        /// Creates an actor pinned to the given executor.
        ///
        /// The actor takes no ownership of the executor's lifecycle —
        /// shutdown is the caller's responsibility.
        public init(executor: Kernel.Thread.Executor) {
            self.executor = executor
        }

        /// The executor as an `UnownedSerialExecutor`, for actor
        /// isolation and TCA26 co-location.
        ///
        /// Per Swift's actor model, the runtime reads this accessor
        /// when scheduling isolated work on the actor and when
        /// consumer actors forward their own `unownedExecutor`.
        public nonisolated var unownedExecutor: UnownedSerialExecutor {
            unsafe executor.asUnownedSerialExecutor()
        }
    }
}
