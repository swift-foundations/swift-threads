extension Kernel.Thread {

    public final class Barrier: @unchecked Sendable {
        private var _arrived: Int = 0
        private let target: Int
        private var released: Bool = false
        private let sync = Synchronizer.Blocking<1>()

        public init(count: Int) {
            precondition(count >= 1, "Barrier count must be at least 1")
            self.target = count
        }
    }
}

extension Kernel.Thread.Barrier {

    public func arrive(timeout: Duration = .seconds(5)) -> Bool {
        sync.lock()
        defer { sync.unlock() }

        _arrived += 1

        if _arrived >= target {
            released = true
            sync.broadcast(condition: 0)
            return true
        }

        while !released {
            if !sync.wait(condition: 0, timeout: timeout) {
                return false
            }
        }
        return true
    }

    public var arrived: Int {
        sync.synchronize { _arrived }
    }
}
