extension Kernel.Thread.Semaphore {

    public enum Error: Swift.Error, Sendable, Equatable {

        case shutdown

        case cancelled

        case timeout
    }
}
