extension Kernel.Thread.Semaphore {
    @usableFromInline
    struct State: Sendable {
        var available: Int
        var outstanding: Int
        var waiters: Int
        var lifecycle: Lifecycle
        var metrics: Metrics

        init(capacity: Int) {
            self.available = capacity
            self.outstanding = 0
            self.waiters = 0
            self.lifecycle = .open
            self.metrics = Metrics()
            self.metrics.available = capacity
        }
    }
}
