//
//  Kernel.Thread.Pool.Outcome.swift
//  swift-threads
//

extension Kernel.Thread.Pool {
    /// Package-internal storage for a move-only operation outcome.
    enum Outcome<Success: ~Copyable, Failure: Swift.Error>: ~Copyable {
        case success(Success)
        case failure(Failure)
    }
}
