extension Kernel.Thread.Semaphore {

    @usableFromInline
    enum Lifecycle: Sendable, Equatable {

        case open

        case closing

        case closed
    }
}
