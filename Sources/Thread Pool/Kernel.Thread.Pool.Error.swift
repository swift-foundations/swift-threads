//
//  Kernel.Thread.Pool.Error.swift
//  swift-threads
//

internal import Async_Semaphore_Primitives

extension Kernel.Thread.Pool {
    /// Errors thrown by pool admission and logical delivery.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The bounded pool has no remaining reservation capacity.
        case capacity

        /// The task was cancelled.
        case cancelled

        /// The total operation budget expired.
        case timeout

        /// The pool has been shut down.
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
