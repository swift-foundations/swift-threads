//
//  Kernel.Thread.Pool.Options.swift
//  swift-threads
//

internal import Cardinal_Add_Primitives
internal import Cardinal_Carrier_Primitives
public import Cardinal_Primitive

extension Kernel.Thread.Pool {
    /// Configuration for the thread pool.
    public struct Options: Sendable {
        /// Number of worker threads.
        ///
        /// If nil, Sharded defaults to processor count.
        public var workers: Kernel.Thread.Count?

        /// Maximum number of admitted operations.
        public let admitted: Cardinal

        /// Maximum number of operations waiting for admission.
        public let queued: Cardinal

        /// Creates thread-pool options.
        ///
        /// - Parameters:
        ///   - workers: The number of worker threads, or nil to use the executor default.
        ///   - admitted: The maximum number of operations holding admission.
        ///   - queued: The maximum number of operations waiting for admission.
        public init(
            workers: Kernel.Thread.Count? = nil,
            admitted: Cardinal = Cardinal(256),
            queued: Cardinal = Cardinal(256)
        ) {
            precondition(admitted > .zero, "Thread-pool admission must be positive")
            let capacity = admitted.add.saturating(queued)
            precondition(capacity <= Cardinal(UInt(Int.max)), "Thread-pool capacity must fit Int")
            self.workers = workers
            self.admitted = admitted
            self.queued = queued
        }
    }
}
