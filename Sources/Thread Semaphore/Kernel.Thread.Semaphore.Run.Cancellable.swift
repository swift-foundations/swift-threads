// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-kernel open source project
//
// Copyright (c) 2024-2025 Coen ten Thije Boonkkamp and the swift-kernel project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

extension Kernel.Thread.Semaphore.Run {
    /// Cancellable variant of scoped permit acquisition.
    ///
    /// Polls for cancellation at a configurable interval while waiting
    /// for a permit.
    ///
    /// ## Usage
    /// ```swift
    /// let token = Kernel.Thread.Semaphore.Cancellation()
    /// let result = try semaphore.run.cancellable(token).poll(.milliseconds(5)) { work() }
    /// // Cancel from another thread:
    /// token.cancel()
    /// ```
    public struct Cancellable: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        let token: Kernel.Thread.Semaphore.Cancellation

        @usableFromInline
        var interval: Duration

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore, token: Kernel.Thread.Semaphore.Cancellation) {
            self.semaphore = semaphore
            self.token = token
            self.interval = .milliseconds(10)
        }
    }

    /// Creates a cancellable acquisition variant.
    ///
    /// - Parameter token: The cancellation token to monitor.
    /// - Returns: A `Cancellable` accessor that checks for cancellation.
    public func cancellable(_ token: Kernel.Thread.Semaphore.Cancellation) -> Cancellable {
        Cancellable(semaphore: semaphore, token: token)
    }
}

extension Kernel.Thread.Semaphore.Run.Cancellable {
    @usableFromInline
    static let minimum: Duration = .milliseconds(1)

    /// Sets the cancellation poll interval.
    ///
    /// - Parameter interval: The interval at which to check cancellation.
    ///   Clamped to a minimum of 1 millisecond.
    /// - Returns: A copy with the updated poll interval.
    public func poll(_ interval: Duration) -> Self {
        var copy = self
        copy.interval = max(interval, Self.minimum)
        return copy
    }

    /// Acquires a permit with cancellation support, executes the body, then releases.
    ///
    /// - Parameter body: The work to perform while holding a permit.
    /// - Returns: The body's return value.
    /// - Throws: `Kernel.Thread.Semaphore.Error.shutdown` if the semaphore
    ///   is shutting down, or `.cancelled` if the token was cancelled.
    @inlinable
    public func callAsFunction<T: Sendable>(
        _ body: @Sendable () -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> T {
        try semaphore._acquire(cancellation: token, poll: interval)
        defer { semaphore._release() }

        let result = body()

        if token.isCancelled {
            throw .cancelled
        }
        return result
    }
}
