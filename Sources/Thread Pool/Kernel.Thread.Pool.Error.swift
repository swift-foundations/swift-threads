internal import Async_Semaphore_Primitives

extension Kernel.Thread.Pool {

    public enum Error: Swift.Error, Sendable, Equatable {

        case capacity

        case cancelled

        case timeout

        case shutdown
    }
}

extension Kernel.Thread.Pool.Error {
    init(from error: Async.Semaphore.Error) {
        switch error {
        case .cancelled: self = .cancelled
        case .timeout: self = .timeout
        case .shutdown: self = .shutdown
        }
    }
}
