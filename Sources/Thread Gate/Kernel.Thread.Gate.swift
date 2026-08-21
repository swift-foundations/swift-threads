extension Kernel.Thread {

    public final class Gate: @unchecked Sendable {
        private var _isOpen: Bool = false
        private let sync = Synchronizer.Blocking<1>()

        public init() {}
    }
}

extension Kernel.Thread.Gate {

    public func open() {
        let didOpen = sync.synchronize {
            guard !_isOpen else { return false }
            _isOpen = true
            return true
        }
        if didOpen {
            sync.broadcast(condition: 0)
        }
    }

    public func wait() {
        sync.lock()
        defer { sync.unlock() }
        while !_isOpen {
            sync.wait(condition: 0)
        }
    }

    public func wait(timeout: Duration) -> Bool {
        sync.lock()
        defer { sync.unlock() }
        while !_isOpen {
            if !sync.wait(condition: 0, timeout: timeout) {
                return _isOpen
            }
        }
        return true
    }

    public var isOpen: Bool {
        sync.synchronize { _isOpen }
    }
}
