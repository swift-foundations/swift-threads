//
//  Kernel.Thread.Pool.swift
//  swift-executors
//

internal import Async_Semaphore_Primitives

extension Kernel.Thread {
    /// Admission-gated thread pool for dispatching arbitrary closures to
    /// dedicated OS threads.
    ///
    /// Composes two building blocks:
    /// - `Kernel.Thread.Executor.Sharded` — round-robin dispatch across N
    ///   worker executors
    /// - `Async.Semaphore` — async-suspending admission gate that bounds the
    ///   number of concurrent in-flight operations
    ///
    /// ## Usage
    /// ```swift
    /// let pool = Kernel.Thread.Pool()
    /// defer { pool.shutdown() }
    /// let result = try await pool.run { blockingSyscall() }
    /// ```
    ///
    /// Consumers who need raw executor access (e.g. for actor pinning or
    /// `Task(executorPreference:)`) should use `Kernel.Thread.Executor.Sharded`
    /// directly.
    public struct Pool: Sendable {
        let executors: Kernel.Thread.Executor.Sharded
        let admission: Async.Semaphore

        /// Creates a thread pool with the given options.
        public init(_ options: Options = .init()) {
            self.executors = Kernel.Thread.Executor.Sharded(.init(count: options.workers))
            self.admission = Async.Semaphore(capacity: options.admissionLimit)
        }
    }
}

// MARK: - Shared

extension Kernel.Thread.Pool {
    /// Process-scoped shared instance.
    ///
    /// Lazily initialized, no shutdown required — lives for the process lifetime.
    public static let shared: Kernel.Thread.Pool = .init()
}

// MARK: - Shutdown

extension Kernel.Thread.Pool {
    /// Shut down, rejecting new work.
    ///
    /// Shuts down the admission semaphore (wakes waiters with `.shutdown`)
    /// and shuts down the executor pool (joins OS threads).
    public func shutdown() {
        admission.shutdown()
        executors.shutdown()
    }
}
