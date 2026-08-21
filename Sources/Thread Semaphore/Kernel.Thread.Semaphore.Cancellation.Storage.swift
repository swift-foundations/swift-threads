public import Synchronization

extension Kernel.Thread.Semaphore.Cancellation {
    @usableFromInline
    final class Storage: Sendable {
        @usableFromInline
        let flag: Atomic<Bool>

        @usableFromInline
        init() {
            self.flag = Atomic(false)
        }
    }
}
