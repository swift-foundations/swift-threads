//
//  Kernel.Thread.Pool.Lifecycle.swift
//  swift-threads
//

internal import Synchronizer_Blocking

extension Kernel.Thread.Pool {
    /// Synchronized reservation and logical-delivery state for one pool.
    ///
    /// ## Safety Invariant
    ///
    /// The synchronizer exclusively protects open, count, and deliveries.
    /// Count equals accepted calls that have not physically completed.
    /// Deliveries contains only accepted calls whose logical requester has
    /// not completed. Closing is monotonic. Every successful reservation is
    /// released exactly once, and continuations are resumed after unlocking.
    final class Lifecycle: @unchecked Sendable {
        private let sync = Synchronizer.Blocking<1>()
        private let maximum: Int
        private var open = true
        private var count = 0
        private var deliveries: [
            ObjectIdentifier: CheckedContinuation<Kernel.Thread.Pool.Error?, Never>
        ] = [:]

        init(maximum: Int) {
            self.maximum = maximum
        }
    }
}

extension Kernel.Thread.Pool.Lifecycle {
    /// Reserves bounded capacity for one call.
    func reserve() throws(Kernel.Thread.Pool.Error) {
        let failure: Kernel.Thread.Pool.Error?

        sync.lock()
        if !open {
            failure = .shutdown
        } else if count == maximum {
            failure = .capacity
        } else {
            count += 1
            failure = nil
        }
        sync.unlock()

        if let failure {
            throw failure
        }
    }

    /// Registers one accepted requester's logical delivery.
    func register(
        _ id: ObjectIdentifier,
        continuation: CheckedContinuation<Kernel.Thread.Pool.Error?, Never>
    ) -> Bool {
        sync.lock()
        guard open else {
            sync.unlock()
            return false
        }
        precondition(deliveries[id] == nil, "Thread-pool delivery identity reused")
        deliveries[id] = continuation
        sync.unlock()
        return true
    }

    /// Establishes admission before shutdown can reject queued work.
    func admit(_ id: ObjectIdentifier) -> Bool {
        sync.lock()
        let admitted = open && deliveries[id] != nil
        sync.unlock()
        return admitted
    }

    /// Claims one requester's logical delivery.
    func resolve(
        _ id: ObjectIdentifier
    ) -> CheckedContinuation<Kernel.Thread.Pool.Error?, Never>? {
        sync.lock()
        let continuation = deliveries.removeValue(forKey: id)
        sync.unlock()
        return continuation
    }

    /// Releases one accepted call after physical completion.
    func release() {
        sync.lock()
        count -= 1
        precondition(count >= 0, "Thread-pool releases outnumber reservations")
        let idle = count == 0
        sync.unlock()

        if idle {
            sync.broadcast(condition: 0)
        }
    }

    /// Closes reservations and claims all unresolved deliveries.
    func close() -> [CheckedContinuation<Kernel.Thread.Pool.Error?, Never>] {
        sync.lock()
        open = false
        let continuations = Array(deliveries.values)
        deliveries.removeAll(keepingCapacity: true)
        sync.unlock()
        return continuations
    }

    /// Blocks until every accepted call has physically completed.
    func wait() {
        sync.lock()
        defer { sync.unlock() }
        while count != 0 {
            sync.wait(condition: 0)
        }
    }
}
