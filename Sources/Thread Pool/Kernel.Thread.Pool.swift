//
//  Kernel.Thread.Pool.swift
//  swift-threads
//

internal import Async_Semaphore_Primitives
internal import Cardinal_Add_Primitives
internal import Cardinal_Primitives_Standard_Library_Integration

extension Kernel.Thread {
    /// Admission-gated pool for dispatching arbitrary closures to dedicated OS threads.
    public struct Pool: Sendable {
        let executors: Kernel.Thread.Executor.Sharded
        let admission: Async.Semaphore
        let lifecycle: Kernel.Thread.Pool.Lifecycle

        /// Creates a thread pool with the given options.
        ///
        /// - Parameter options: The worker, admission, and queue bounds.
        public init(_ options: Options = .init()) {
            let admitted = Int(clamping: options.admitted)
            let maximum = Int(clamping: options.admitted.add.saturating(options.queued))
            self.executors = Kernel.Thread.Executor.Sharded(.init(count: options.workers))
            self.admission = Async.Semaphore(capacity: admitted)
            self.lifecycle = Kernel.Thread.Pool.Lifecycle(maximum: maximum)
        }
    }
}

extension Kernel.Thread.Pool {
    /// Process-scoped shared instance.
    ///
    /// The process owner may share this bounded pool. Consumers must not shut
    /// it down.
    public static let shared: Kernel.Thread.Pool = .init()
}

extension Kernel.Thread.Pool {
    /// Shuts down the pool after draining all accepted work.
    ///
    /// New reservations and queued admission waiters are rejected. Logical
    /// requesters for admitted work resume with shutdown while workers retain
    /// physical ownership until their operations finish. This method drains
    /// those finite workers before joining their threads.
    public func shutdown() {
        let deliveries = lifecycle.close()
        admission.shutdown()
        deliveries.forEach { $0.resume(returning: .shutdown) }
        lifecycle.wait()
        executors.shutdown()
    }
}
