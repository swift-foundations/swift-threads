internal import Async_Semaphore_Primitives
internal import Cardinal_Add_Primitives
internal import Cardinal_Primitives_Standard_Library_Integration

extension Kernel.Thread {

    public struct Pool: Sendable {
        let executors: Kernel.Thread.Executor.Sharded
        let admission: Async.Semaphore
        let lifecycle: Kernel.Thread.Pool.Lifecycle

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

    public static let shared: Kernel.Thread.Pool = .init()
}

extension Kernel.Thread.Pool {

    public func shutdown() {
        let deliveries = lifecycle.close()
        admission.shutdown()
        deliveries.forEach { $0.resume(returning: .shutdown) }
        lifecycle.wait()
        executors.shutdown()
    }
}
