extension Kernel.Thread.Semaphore {
    @usableFromInline
    enum Effect: Sendable {
        case none
        case signal(Condition)
        case broadcast(Condition)
    }
}
