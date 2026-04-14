//
//  Kernel.Thread.Pool.Options.swift
//  swift-executors
//

extension Kernel.Thread.Pool {
    /// Configuration for the thread pool.
    public struct Options: Sendable {
        /// Number of worker threads. If nil, Sharded defaults to processor count.
        public var workers: Kernel.Thread.Count?

        /// Maximum concurrent in-flight operations.
        public var admissionLimit: Int

        public init(
            workers: Kernel.Thread.Count? = nil,
            admissionLimit: Int = 256
        ) {
            self.workers = workers
            self.admissionLimit = admissionLimit
        }
    }
}
