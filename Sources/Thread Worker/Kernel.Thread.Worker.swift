import Synchronization

extension Kernel.Thread {

    public struct Worker: ~Copyable, Sendable {

        private var handle: Handle

        private let token: Token

        private init(handle: consuming Handle, token: Token) {
            self.handle = handle
            self.token = token
        }
    }
}

extension Kernel.Thread.Worker {

    public static func start(
        _ body: @escaping @Sendable (Token) -> Void
    ) throws(Kernel.Thread.Error) -> Self {
        let token = Token()

        let handle = try Kernel.Thread.spawn {
            body(token)
        }

        return Self(handle: handle, token: token)
    }
}

extension Kernel.Thread.Worker {

    public func stop() {
        token.stop()
    }

    public var isStopping: Bool {
        token.shouldStop
    }

    public consuming func join() throws(Kernel.Thread.Error) {
        precondition(
            handle.isCurrent == false,
            "Kernel.Thread.Worker.join() called from the worker's own thread - this would deadlock"
        )
        try handle.join()
    }
}
