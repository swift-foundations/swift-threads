extension Kernel.Thread.Semaphore {

    public struct Metrics: Sendable, Equatable {

        public var acquisitions: UInt64 = 0

        public var releases: UInt64 = 0

        public var rejected: UInt64 = 0

        public var timeouts: UInt64 = 0

        public var cancellations: UInt64 = 0

        public var outstanding: Int = 0

        public var available: Int = 0

        public var waiters: Int = 0

        public var peak: Int = 0
    }
}
