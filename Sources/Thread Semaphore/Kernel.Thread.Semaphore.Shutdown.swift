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
    /// Shutdown accessor for graceful semaphore termination.
    ///
    /// ## Usage
    /// ```swift
    /// // Initiate shutdown (non-blocking)
    /// semaphore.shutdown()
    ///
    /// // Initiate shutdown and wait for all permits to be released
    /// semaphore.shutdown.wait()
    /// ```
    public struct Shutdown: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore) {
            self.semaphore = semaphore
        }
    }
}

extension Kernel.Thread.Semaphore {
    /// Shutdown accessor.
    public var shutdown: Shutdown { Shutdown(semaphore: self) }
}

extension Kernel.Thread.Semaphore.Shutdown {
    /// Initiates shutdown. New acquisitions will throw `.shutdown`.
    ///
    /// Outstanding permits continue to be held until released.
    /// Blocked waiters are woken and will receive `.shutdown`.
    public func callAsFunction() {
        semaphore._shutdown()
    }

    /// Initiates shutdown and blocks until all outstanding permits are released.
    ///
    /// If the semaphore is still open, this initiates shutdown first.
    public func wait() {
        semaphore._wait()
    }
}
