internal import Synchronization

extension Kernel.Thread.Semaphore {

    public struct Cancellation: Sendable {
        @usableFromInline
        let storage: Storage

        public init() {
            self.storage = Storage()
        }
    }
}

extension Kernel.Thread.Semaphore.Cancellation {

    public var isCancelled: Bool {
        storage.flag.load(ordering: .acquiring)
    }

    public func cancel() {
        storage.flag.store(true, ordering: .releasing)
    }
}
