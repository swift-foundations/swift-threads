extension Kernel.Thread {

    public final class Semaphore: @unchecked Sendable {
        @usableFromInline
        let sync: Synchronizer.Blocking<2>

        @usableFromInline
        var _state: State

        public let capacity: Int

        public init(capacity: Int) {
            precondition(capacity >= 1, "Semaphore capacity must be at least 1")
            self.capacity = capacity
            self.sync = Synchronizer.Blocking<2>()
            self._state = State(capacity: capacity)
        }
    }
}

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _acquire() throws(Error) {
        sync.lock()
        defer { sync.unlock() }

        while true {
            if _state.lifecycle != .open {
                _state.metrics.rejected += 1
                throw .shutdown
            }
            if _state.available > 0 {
                _state.available -= 1
                _state.outstanding += 1
                _state.metrics.acquisitions += 1
                _state.metrics.outstanding = _state.outstanding
                _state.metrics.available = _state.available
                if _state.outstanding > _state.metrics.peak {
                    _state.metrics.peak = _state.outstanding
                }
                return
            }
            _state.waiters += 1
            sync.wait(condition: Condition.available.rawValue)
            _state.waiters -= 1
            precondition(_state.waiters >= 0, "Waiter count underflow")
        }
    }

    @usableFromInline
    func _acquire(timeout duration: Duration) throws(Error) -> Bool {
        sync.lock()
        defer { sync.unlock() }

        let deadline = Clock.Continuous.now.advanced(by: duration)

        while true {
            if _state.lifecycle != .open {
                _state.metrics.rejected += 1
                throw .shutdown
            }
            if _state.available > 0 {
                _state.available -= 1
                _state.outstanding += 1
                _state.metrics.acquisitions += 1
                _state.metrics.outstanding = _state.outstanding
                _state.metrics.available = _state.available
                if _state.outstanding > _state.metrics.peak {
                    _state.metrics.peak = _state.outstanding
                }
                return true
            }
            let remaining = deadline - Clock.Continuous.now
            if remaining <= .zero {
                _state.metrics.timeouts += 1
                return false
            }

            _state.waiters += 1
            _ = sync.wait(condition: Condition.available.rawValue, timeout: remaining)
            _state.waiters -= 1
            precondition(_state.waiters >= 0, "Waiter count underflow")
        }
    }

    @usableFromInline
    func _acquire(cancellation token: Cancellation, poll interval: Duration) throws(Error) {
        sync.lock()
        defer { sync.unlock() }

        while true {
            if _state.lifecycle != .open {
                _state.metrics.rejected += 1
                throw .shutdown
            }
            if token.isCancelled {
                _state.metrics.cancellations += 1
                throw .cancelled
            }
            if _state.available > 0 {
                _state.available -= 1
                _state.outstanding += 1
                _state.metrics.acquisitions += 1
                _state.metrics.outstanding = _state.outstanding
                _state.metrics.available = _state.available
                if _state.outstanding > _state.metrics.peak {
                    _state.metrics.peak = _state.outstanding
                }
                return
            }

            _state.waiters += 1
            _ = sync.wait(condition: Condition.available.rawValue, timeout: interval)
            _state.waiters -= 1
            precondition(_state.waiters >= 0, "Waiter count underflow")
        }
    }
}

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _release() {
        let effect: Effect = sync.synchronize {
            _state.outstanding -= 1
            _state.available += 1
            _state.metrics.releases += 1
            _state.metrics.outstanding = _state.outstanding
            _state.metrics.available = _state.available

            guard _state.lifecycle == .open else {
                return _close()
            }
            return .signal(.available)
        }
        perform(effect)
    }
}

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _shutdown() {
        let effect: Effect = sync.synchronize {
            guard _state.lifecycle == .open else {
                return .none
            }
            _state.lifecycle = .closing

            guard _state.outstanding == 0 else {
                return .broadcast(.available)
            }
            _state.lifecycle = .closed
            return .broadcast(.shutdown)
        }
        perform(effect)
    }

    @usableFromInline
    func _wait() {
        sync.lock()
        defer { sync.unlock() }

        if _state.lifecycle == .open {
            sync.unlock()
            _shutdown()
            sync.lock()
        }

        while _state.lifecycle != .closed {
            sync.wait(condition: Condition.shutdown.rawValue)
        }
    }
}

extension Kernel.Thread.Semaphore {
    @usableFromInline
    func _close() -> Effect {
        guard _state.lifecycle == .closing,
            _state.outstanding == 0
        else {
            return .none
        }
        _state.lifecycle = .closed
        return .broadcast(.shutdown)
    }
}

extension Kernel.Thread.Semaphore {
    @inline(always)
    func perform(_ effect: Effect) {
        switch effect {
        case .none:
            return

        case .signal(let condition):

            sync.signal(condition: condition.rawValue)

        case .broadcast(let condition):

            sync.broadcast(condition: condition.rawValue)
        }
    }
}

extension Kernel.Thread.Semaphore {

    public var metrics: Metrics {
        sync.lock()
        defer { sync.unlock() }
        var m = _state.metrics
        m.waiters = _state.waiters
        return m
    }
}
