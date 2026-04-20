// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-kernel open source project
//
// Copyright (c) 2024-2025 Coen ten Thije Boonkkamp and the swift-kernel project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Kernel
import Synchronization
import Testing
import Thread_Synchronization

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// MARK: - Test Suites for Synchronization Waiter Tracking

@Suite("Synchronization Waiter Tracking")
struct SynchronizationWaiterTrackingTests {}

// MARK: - Unit Tests

extension SynchronizationWaiterTrackingTests {
    @Suite("Unit")
    struct Unit {}
}

extension SynchronizationWaiterTrackingTests.Unit {
    @Test
    func `waiters starts at zero`() {
        let sync = Kernel.Thread.SingleSync()
        sync.lock()
        #expect(sync.waiters(condition: 0) == 0)
        sync.unlock()
    }

    @Test
    func `signalIfWaiters returns false when no waiters`() {
        let sync = Kernel.Thread.SingleSync()
        sync.lock()
        let result = sync.signalIfWaiters(condition: 0)
        sync.unlock()
        #expect(result == false)
    }

    @Test
    func `broadcastIfWaiters returns false when no waiters`() {
        let sync = Kernel.Thread.SingleSync()
        sync.lock()
        let result = sync.broadcastIfWaiters(condition: 0)
        sync.unlock()
        #expect(result == false)
    }

    @Test
    func `DualSync Channel waiters starts at zero`() {
        let sync = Kernel.Thread.DualSync()
        sync.lock()
        #expect(sync.worker.waiters == 0)
        #expect(sync.deadline.waiters == 0)
        sync.unlock()
    }

    @Test
    func `DualSync Channel signalIfWaiters returns false when empty`() {
        let sync = Kernel.Thread.DualSync()
        sync.lock()
        #expect(sync.worker.signalIfWaiters() == false)
        #expect(sync.deadline.signalIfWaiters() == false)
        sync.unlock()
    }

    @Test
    func `DualSync Channel broadcastIfWaiters returns false when empty`() {
        let sync = Kernel.Thread.DualSync()
        sync.lock()
        #expect(sync.worker.broadcastIfWaiters() == false)
        #expect(sync.deadline.broadcastIfWaiters() == false)
        sync.unlock()
    }
}

// MARK: - Integration Tests

extension SynchronizationWaiterTrackingTests {
    @Suite("Integration")
    struct Integration {}
}

/// Small sleep helper using nanosleep
private func smallSleep(milliseconds: UInt32) {
    #if canImport(Darwin)
        usleep(milliseconds * 1000)
    #elseif canImport(Glibc)
        usleep(milliseconds * 1000)
    #endif
}

extension SynchronizationWaiterTrackingTests.Integration {
    @Test
    func `waitTracked increments waiters`() throws {
        let sync = Kernel.Thread.SingleSync()
        let waiterReady = Atomic<Bool>(false)
        let shouldWake = Atomic<Bool>(false)

        let handle = try Kernel.Thread.spawn {
            sync.lock()
            waiterReady.store(true, ordering: .releasing)
            // This will increment waiters, wait, then decrement
            while !shouldWake.load(ordering: .acquiring) {
                sync.waitTracked(condition: 0)
            }
            sync.unlock()
        }

        // Wait for thread to be ready and waiting
        while !waiterReady.load(ordering: .acquiring) {
            smallSleep(milliseconds: 1)
        }

        // Give thread time to enter wait
        smallSleep(milliseconds: 20)

        // Check waiter count under lock
        sync.lock()
        let count = sync.waiters(condition: 0)
        shouldWake.store(true, ordering: .releasing)
        sync.broadcast(condition: 0)
        sync.unlock()

        handle.join()

        #expect(count == 1)
    }

    @Test
    func `waitTracked decrements waiters after wakeup`() throws {
        let sync = Kernel.Thread.SingleSync()
        let threadDone = Atomic<Bool>(false)

        let handle = try Kernel.Thread.spawn {
            sync.lock()
            // Use timeout to auto-wake
            _ = sync.waitTracked(condition: 0, timeout: .milliseconds(10))
            sync.unlock()
            threadDone.store(true, ordering: .releasing)
        }

        handle.join()

        // After thread exits, waiter count should be back to 0
        sync.lock()
        let count = sync.waiters(condition: 0)
        sync.unlock()

        #expect(count == 0)
        #expect(threadDone.load(ordering: .acquiring) == true)
    }

    @Test
    func `signalIfWaiters returns true and wakes one waiter`() throws {
        let sync = Kernel.Thread.SingleSync()
        let waiterReady = Atomic<Bool>(false)
        let waiterWoken = Atomic<Bool>(false)

        let handle = try Kernel.Thread.spawn {
            sync.lock()
            waiterReady.store(true, ordering: .releasing)
            sync.waitTracked(condition: 0)
            waiterWoken.store(true, ordering: .releasing)
            sync.unlock()
        }

        // Wait for thread to enter wait
        while !waiterReady.load(ordering: .acquiring) {
            smallSleep(milliseconds: 1)
        }
        smallSleep(milliseconds: 20)

        // Signal and check return value
        sync.lock()
        let hadWaiters = sync.signalIfWaiters(condition: 0)
        sync.unlock()

        handle.join()

        #expect(hadWaiters == true)
        #expect(waiterWoken.load(ordering: .acquiring) == true)
    }

    @Test
    func `broadcastIfWaiters returns true and wakes all waiters`() throws {
        let sync = Kernel.Thread.SingleSync()
        let waitersReady = Atomic<Int>(0)
        let waitersWoken = Atomic<Int>(0)
        let numWaiters = 3

        // Spawn threads - use consuming to transfer ownership
        let handle1 = try Kernel.Thread.spawn {
            sync.lock()
            waitersReady.wrappingAdd(1, ordering: .releasing)
            sync.waitTracked(condition: 0)
            waitersWoken.wrappingAdd(1, ordering: .releasing)
            sync.unlock()
        }
        let handle2 = try Kernel.Thread.spawn {
            sync.lock()
            waitersReady.wrappingAdd(1, ordering: .releasing)
            sync.waitTracked(condition: 0)
            waitersWoken.wrappingAdd(1, ordering: .releasing)
            sync.unlock()
        }
        let handle3 = try Kernel.Thread.spawn {
            sync.lock()
            waitersReady.wrappingAdd(1, ordering: .releasing)
            sync.waitTracked(condition: 0)
            waitersWoken.wrappingAdd(1, ordering: .releasing)
            sync.unlock()
        }

        // Wait for all threads to enter wait
        while waitersReady.load(ordering: .acquiring) < numWaiters {
            smallSleep(milliseconds: 1)
        }
        smallSleep(milliseconds: 30)

        // Check waiter count and broadcast
        sync.lock()
        let count = sync.waiters(condition: 0)
        let hadWaiters = sync.broadcastIfWaiters(condition: 0)
        sync.unlock()

        handle1.join()
        handle2.join()
        handle3.join()

        #expect(count == numWaiters)
        #expect(hadWaiters == true)
        #expect(waitersWoken.load(ordering: .acquiring) == numWaiters)
    }

    @Test
    func `timeout waitTracked still decrements count`() throws {
        let sync = Kernel.Thread.SingleSync()
        let timedOut = Atomic<Bool>(false)

        let handle = try Kernel.Thread.spawn {
            sync.lock()
            let result = sync.waitTracked(condition: 0, timeout: .milliseconds(10))
            timedOut.store(!result, ordering: .releasing)  // false = timeout
            sync.unlock()
        }

        handle.join()

        sync.lock()
        let count = sync.waiters(condition: 0)
        sync.unlock()

        #expect(count == 0)
        #expect(timedOut.load(ordering: .acquiring) == true)
    }

    @Test
    func `mixed wait and waitTracked - broadcast still wakes tracked waiters`() throws {
        let sync = Kernel.Thread.SingleSync()
        let trackedReady = Atomic<Bool>(false)
        let trackedWoken = Atomic<Bool>(false)

        // Spawn a thread using waitTracked
        let handle = try Kernel.Thread.spawn {
            sync.lock()
            trackedReady.store(true, ordering: .releasing)
            sync.waitTracked(condition: 0)
            trackedWoken.store(true, ordering: .releasing)
            sync.unlock()
        }

        // Wait for thread to enter wait
        while !trackedReady.load(ordering: .acquiring) {
            smallSleep(milliseconds: 1)
        }
        smallSleep(milliseconds: 20)

        // Use unconditional broadcast (not broadcastIfWaiters)
        sync.lock()
        sync.broadcast(condition: 0)
        sync.unlock()

        handle.join()

        // Tracked waiter should still be woken by unconditional broadcast
        #expect(trackedWoken.load(ordering: .acquiring) == true)
    }

    @Test
    func `DualSync Channel waitTracked works`() throws {
        let sync = Kernel.Thread.DualSync()
        let waiterReady = Atomic<Bool>(false)
        let waiterWoken = Atomic<Bool>(false)

        let handle = try Kernel.Thread.spawn {
            sync.lock()
            waiterReady.store(true, ordering: .releasing)
            sync.worker.waitTracked()
            waiterWoken.store(true, ordering: .releasing)
            sync.unlock()
        }

        // Wait for thread to enter wait
        while !waiterReady.load(ordering: .acquiring) {
            smallSleep(milliseconds: 1)
        }
        smallSleep(milliseconds: 20)

        // Check and wake via accessor
        sync.lock()
        let count = sync.worker.waiters
        let hadWaiters = sync.worker.broadcastIfWaiters()
        sync.unlock()

        handle.join()

        #expect(count == 1)
        #expect(hadWaiters == true)
        #expect(waiterWoken.load(ordering: .acquiring) == true)
    }
}
