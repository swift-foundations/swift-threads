//
//  Kernel.Thread.Pool.Error.swift
//  swift-executors
//

internal import Async_Semaphore_Primitives

extension Kernel.Thread.Pool {
    /// Errors thrown by pool admission.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The task was cancelled before admission.
        case cancelled

        /// The deadline expired before admission.
        case timeout

        /// The pool has been shut down.
        case shutdown
    }
}

// MARK: - Conversion from Semaphore Error

extension Kernel.Thread.Pool.Error {
    init(from semaphoreError: Async.Semaphore.Error) {
        switch semaphoreError {
        case .cancelled: self = .cancelled
        case .timeout: self = .timeout
        case .shutdown: self = .shutdown
        }
    }
}
