public import Executors

extension Kernel.Thread {

    public actor Actor {

        public let executor: Kernel.Thread.Executor

        public init(executor: Kernel.Thread.Executor) {
            self.executor = executor
        }
    }
}

extension Kernel.Thread.Actor {

    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        unsafe executor.asUnownedSerialExecutor()
    }
}
