internal import Cardinal_Add_Primitives
internal import Cardinal_Carrier_Primitives
public import Cardinal_Primitive

extension Kernel.Thread.Pool {

    public struct Options: Sendable {

        public var workers: Kernel.Thread.Count?

        public let admitted: Cardinal

        public let queued: Cardinal

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
