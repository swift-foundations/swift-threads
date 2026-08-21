extension Kernel.Thread.Semaphore {
    @usableFromInline
    enum Condition: Int, Sendable {
        case available = 0
        case shutdown = 1
    }
}
