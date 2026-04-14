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
    /// Timed variant of scoped permit acquisition.
    ///
    /// Returns `nil` if the permit could not be acquired within the
    /// specified duration.
    ///
    /// ## Usage
    /// ```swift
    /// let result = try semaphore.run.timeout(.seconds(5)) { work() }
    /// // result is nil if timed out
    /// ```
    public struct Timeout: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        let duration: Duration

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore, duration: Duration) {
            self.semaphore = semaphore
            self.duration = duration
        }
    }

    /// Creates a timed acquisition variant.
    ///
    /// - Parameter duration: The maximum time to wait for a permit.
    /// - Returns: A `Timeout` accessor that returns `nil` on timeout.
    public func timeout(_ duration: Duration) -> Timeout {
        Timeout(semaphore: semaphore, duration: duration)
    }
}

extension Kernel.Thread.Semaphore.Run.Timeout {
    /// Acquires a permit with a timeout, executes the body, then releases.
    ///
    /// - Parameter body: The work to perform while holding a permit.
    /// - Returns: The body's return value, or `nil` if the timeout expired.
    /// - Throws: `Kernel.Thread.Semaphore.Error.shutdown` if the semaphore
    ///   is shutting down.
    @inlinable
    public func callAsFunction<T: Sendable>(
        _ body: @Sendable () -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> T? {
        guard try semaphore._acquire(timeout: duration) else {
            return nil
        }
        defer { semaphore._release() }
        return body()
    }
}
