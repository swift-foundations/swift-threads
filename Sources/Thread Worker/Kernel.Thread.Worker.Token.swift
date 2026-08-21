import Synchronization

extension Kernel.Thread.Worker {

    public final class Token: Sendable {
        private let stopped: Atomic<Bool>

        init() {
            self.stopped = Atomic(false)
        }
    }
}

extension Kernel.Thread.Worker.Token {

    public var shouldStop: Bool {
        stopped.load(ordering: .acquiring)
    }

    func stop() {
        stopped.store(true, ordering: .releasing)
    }
}
