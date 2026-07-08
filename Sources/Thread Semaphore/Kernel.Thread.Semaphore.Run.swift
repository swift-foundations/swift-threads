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

extension Kernel.Thread.Semaphore {
    /// Scoped permit acquisition accessor.
    ///
    /// Acquires a permit before executing the body and releases it after,
    /// regardless of whether the body succeeds or throws.
    ///
    /// ## Usage
    /// ```swift
    /// let result = try semaphore.run { expensiveWork() }
    /// ```
    public struct Run: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore) {
            self.semaphore = semaphore
        }
    }
}

extension Kernel.Thread.Semaphore {
    /// Scoped acquire/release accessor.
    public var run: Run { Run(semaphore: self) }
}

extension Kernel.Thread.Semaphore.Run {
    /// Acquires a permit, executes the body, then releases the permit.
    ///
    /// - Parameter body: The work to perform while holding a permit.
    /// - Returns: The body's return value.
    /// - Throws: `Kernel.Thread.Semaphore.Error.shutdown` if the semaphore
    ///   is shutting down.
    @inlinable
    public func callAsFunction<T: Sendable>(
        _ body: @Sendable () -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> T {
        try semaphore._acquire()
        defer { semaphore._release() }
        return body()
    }

    /// Acquires a permit, executes a throwing body, then releases the permit.
    ///
    /// The body's error is captured in a `Result` so the permit is always
    /// released, even if the body throws.
    ///
    /// - Parameter body: The throwing work to perform while holding a permit.
    /// - Returns: A `Result` containing the body's return value or error.
    /// - Throws: `Kernel.Thread.Semaphore.Error.shutdown` if the semaphore
    ///   is shutting down.
    @inlinable
    public func callAsFunction<T: Sendable, E: Swift.Error>(
        _ body: @Sendable () throws(E) -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> Result<T, E> {
        try semaphore._acquire()
        defer { semaphore._release() }
        do throws(E) {
            return .success(try body())
        } catch {
            return .failure(error)
        }
    }
}
