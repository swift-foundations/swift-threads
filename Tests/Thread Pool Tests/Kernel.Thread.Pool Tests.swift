//
//  Kernel.Thread.Pool Tests.swift
//  swift-threads
//

import Async_Semaphore_Primitives
import Kernel_Test_Support
import Testing
import Thread_Gate

@testable import Thread_Pool

extension Kernel.Thread.Pool {
    enum Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Kernel.Thread.Pool.Test.Unit {
    @Test
    func `shared pool exists`() {
        _ = Kernel.Thread.Pool.shared
    }

    @Test
    func `custom pool with options`() throws {
        let pool = Kernel.Thread.Pool(.init(workers: try .init(2), admissionLimit: 8))
        pool.shutdown()
    }
}

// MARK: - Edge Case Tests

extension Kernel.Thread.Pool.Test.`Edge Case` {
    @Test
    func `shutdown rejects new work`() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try .init(1), admissionLimit: 4))
        pool.shutdown()

        do throws(Kernel.Thread.Pool.Error) {
            _ = try await pool.run { 1 }
            Issue.record("Expected shutdown error")
        } catch {
            #expect(error == .shutdown)
        }
    }

    @Test
    func `throwing operation propagates as .right`() async throws {
        struct TestError: Swift.Error, Sendable, Equatable {}
        let pool = Kernel.Thread.Pool(.init(workers: try .init(1), admissionLimit: 4))
        defer { pool.shutdown() }

        do throws(Either<Kernel.Thread.Pool.Error, TestError>) {
            _ = try await pool.run { () throws(TestError) -> Int in throw TestError() }
            Issue.record("Expected error")
        } catch {
            switch error {
            case .left: Issue.record("Expected .right, got .left")
            case .right(let e): #expect(e == TestError())
            }
        }
    }

    // F-004: shutdown() must drain admitted in-flight work before joining
    // executor threads, rather than proceeding as soon as the admission
    // semaphore is shut down. This exercises `shutdown()`'s real code path
    // (including its `inFlight.waitUntilIdle()` call) while controlling
    // timing deterministically via direct `inFlight.enter()/leave()` calls
    // — the same calls `run(...)` makes internally — instead of racing
    // against OS thread scheduling.
    @Test
    func `shutdown blocks until admitted in-flight work drains before joining executors`() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try .init(1), admissionLimit: 1))
        let shutdownFinished = Kernel.Thread.Gate()

        // Simulate a `run` call that has been admitted (or is still
        // attempting admission) and has not yet completed.
        pool.inFlight.enter()

        Task.detached {
            pool.shutdown()
            shutdownFinished.open()
        }

        // If shutdown() does not drain in-flight work, it returns almost
        // immediately — well before we ever release the simulated run.
        #expect(shutdownFinished.wait(timeout: .milliseconds(200)) == false)

        pool.inFlight.leave()

        #expect(shutdownFinished.wait(timeout: .seconds(5)) == true)
    }

    // F-004 rev-1 (behavioral wiring): exercises the full
    // admission -> inFlight.enter -> defer inFlight.leave -> waitUntilIdle
    // path through a REAL `run(...)` call, with no direct touch of the
    // internal counter. A real operation is admitted and then held on the
    // worker thread by a gate; `shutdown()` must not return while that
    // admitted operation is still executing, and must return promptly once
    // it completes. Every potentially-hanging wait is deadline-bounded
    // (the suite's `Gate.wait(timeout:)` idiom) so a regression fails
    // rather than hangs.
    @Test
    func `shutdown does not return while an admitted run operation is still executing`() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try .init(1), admissionLimit: 4))
        let operationStarted = Kernel.Thread.Gate()
        let operationRelease = Kernel.Thread.Gate()
        let shutdownFinished = Kernel.Thread.Gate()

        // A real run: admitted through the semaphore, dispatched to a
        // worker thread, held mid-execution by `operationRelease`.
        let runTask = Task.detached {
            try? await pool.run { () -> Int in
                operationStarted.open()
                operationRelease.wait()
                return 42
            }
        }

        // The operation is admitted and executing on the worker thread.
        #expect(operationStarted.wait(timeout: .seconds(5)) == true)

        Task.detached {
            pool.shutdown()
            shutdownFinished.open()
        }

        // shutdown() must NOT return while the admitted operation is
        // still blocked mid-execution.
        #expect(shutdownFinished.wait(timeout: .milliseconds(200)) == false)

        operationRelease.open()

        // Once the operation completes and run() unwinds (defer leave()),
        // shutdown() must return promptly.
        #expect(shutdownFinished.wait(timeout: .seconds(5)) == true)
        #expect(await runTask.value == 42)
    }

    // F-004 rev-1 (wiring discriminator): a run suspended in
    // `admission.wait()` occupies NO shard thread, so
    // `Sharded.shutdown()`'s blocking join cannot mask a missing drain —
    // this test goes RED if `run(...)`'s inFlight enter()/leave() wiring
    // is removed, where the blocked-operation test above stays green
    // (verified empirically; see the remediation report).
    //
    // Mechanism: `run()` is `nonisolated(nonsending)`, so the pending
    // run's post-rejection unwinding — including its
    // `defer { inFlight.leave() }` — can only execute on its caller's
    // executor. Pinning the caller to a harness executor and occupying
    // that executor's single thread makes "the rejected run has not yet
    // unwound" a deterministically held state, not a scheduling race.
    @Test
    func `shutdown waits for a run still in admission to unwind before returning`() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try .init(1), admissionLimit: 1))
        let harnessOccupied = Kernel.Thread.Gate()
        let harnessRelease = Kernel.Thread.Gate()
        let shutdownFinished = Kernel.Thread.Gate()

        // Take the pool's only admission permit directly, so the next
        // run() suspends inside admission.wait() with no operation on
        // any shard thread.
        try await pool.admission.wait()

        // Harness executor: the caller context for the pending run.
        let harness = Kernel.Thread.Executor(mode: .task)

        let runTask = Task(executorPreference: harness) {
            try? await pool.run { () -> Int in 7 }
        }

        // Deterministic observation that the run has entered (enter()
        // precedes admission.wait() in run()) and is suspended as the
        // semaphore's sole waiter.
        var waiters = 0
        for _ in 0..<500 {
            waiters = pool.admission.metrics.currentWaiters
            if waiters == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(waiters == 1)

        // Occupy the harness thread so the pending run cannot unwind
        // until released below.
        Task(executorPreference: harness) {
            harnessOccupied.open()
            harnessRelease.wait()
        }
        #expect(harnessOccupied.wait(timeout: .seconds(5)) == true)

        Task.detached {
            pool.shutdown()
            shutdownFinished.open()
        }

        // With the wiring intact, shutdown() is held in waitUntilIdle():
        // the rejected run cannot reach its defer leave() while the
        // harness thread is occupied. Without run()'s enter()/leave()
        // wiring, the in-flight count is zero and every shard is idle,
        // so shutdown() returns immediately — failing this expectation.
        #expect(shutdownFinished.wait(timeout: .milliseconds(200)) == false)

        harnessRelease.open()

        #expect(shutdownFinished.wait(timeout: .seconds(5)) == true)
        // The pending run was rejected at admission with .shutdown.
        #expect(await runTask.value == nil)

        harness.shutdown()
    }
}

// MARK: - Integration Tests

extension Kernel.Thread.Pool.Test.Integration {
    @Test
    func `run completes and returns value`() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try .init(2), admissionLimit: 8))
        defer { pool.shutdown() }

        let result = try await pool.run { 42 }
        #expect(result == 42)
    }

    @Test
    func `multiple runs complete independently`() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try .init(2), admissionLimit: 8))
        defer { pool.shutdown() }

        let r1 = try await pool.run { 1 }
        let r2 = try await pool.run { 2 }
        let r3 = try await pool.run { 3 }
        #expect(r1 == 1)
        #expect(r2 == 2)
        #expect(r3 == 3)
    }

    @Test
    func `non-Sendable return via async run`() async throws {
        final class Box {
            var value: Int
            init(_ v: Int) { self.value = v }
        }
        let pool = Kernel.Thread.Pool(.init(workers: try .init(1), admissionLimit: 4))
        defer { pool.shutdown() }

        let box: Box = try await pool.run { Box(99) }
        #expect(box.value == 99)
    }
}
