//
//  Kernel.Thread.Pool Tests.swift
//  swift-threads
//

import Async_Semaphore_Primitives
import Either_Primitives
import Kernel_Test_Support
import Testing
import Thread_Gate

@testable import Thread_Pool

extension Kernel.Thread.Pool {
    enum Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

extension Kernel.Thread.Pool.Test {
    enum Admission {}

    struct Failure: Swift.Error, Equatable {}

    struct Resource: ~Copyable {
        let census: KernelThreadTest.Harness<Int>

        init(_ census: KernelThreadTest.Harness<Int>) {
            self.census = census
        }

        deinit {
            census.update { $0 += 1 }
        }
    }
}

extension Kernel.Thread.Pool.Test.Unit {
    @Test
    func `custom bounds are accepted`() {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(2), admitted: .init(UInt(2)), queued: .init(UInt(3)))
        )
        pool.shutdown()
    }

    @Test
    func `shutdown rejects new work`() async {
        let pool = Kernel.Thread.Pool(.init(workers: .init(1)))
        pool.shutdown()

        do throws(Kernel.Thread.Pool.Error) {
            _ = try await pool.run { 1 }
            Issue.record("Expected shutdown error")
        } catch {
            #expect(error == .shutdown)
        }
    }

    @Test
    func `throwing operation preserves its error side`() async {
        let pool = Kernel.Thread.Pool(.init(workers: .init(1)))
        defer { pool.shutdown() }

        do throws(Either<Kernel.Thread.Pool.Error, Kernel.Thread.Pool.Test.Failure>) {
            _ = try await pool.run { () throws(Kernel.Thread.Pool.Test.Failure) -> Int in
                throw Kernel.Thread.Pool.Test.Failure()
            }
            Issue.record("Expected operation error")
        } catch {
            switch error {
            case .left:
                Issue.record("Expected operation error")
            case .right(let failure):
                #expect(failure == Kernel.Thread.Pool.Test.Failure())
            }
        }
    }
}

extension Kernel.Thread.Pool.Test.`Edge Case` {
    @Test
    func `capacity rejects work beyond admitted and queued bounds`() async {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        let started = Kernel.Thread.Gate()
        let release = Kernel.Thread.Gate()

        let first = Task { () -> Int? in
            do throws(Kernel.Thread.Pool.Error) {
                return try await pool.run {
                    started.open()
                    release.wait()
                    return 1
                }
            } catch {
                Issue.record("First operation failed: \(error)")
                return nil
            }
        }
        #expect(started.wait(timeout: .seconds(5)))

        let second = Task { () -> Int? in
            do throws(Kernel.Thread.Pool.Error) {
                return try await pool.run { 2 }
            } catch {
                Issue.record("Second operation failed: \(error)")
                return nil
            }
        }
        await Kernel.Thread.Pool.Test.Admission.wait(in: pool)

        do throws(Kernel.Thread.Pool.Error) {
            _ = try await pool.run { 3 }
            Issue.record("Expected capacity error")
        } catch {
            #expect(error == .capacity)
        }

        release.open()
        let firstValue = await first.value
        let secondValue = await second.value
        #expect(firstValue == 1)
        #expect(secondValue == 2)
        pool.shutdown()
    }

    @Test
    func `cancellation abandons delivery and destroys a late move-only result once`() async {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(0)))
        )
        let started = Kernel.Thread.Gate()
        let release = Kernel.Thread.Gate()
        let finished = Kernel.Thread.Gate()
        let census = KernelThreadTest.Harness(0)

        let request = Task { () -> Kernel.Thread.Pool.Error? in
            defer { finished.open() }
            do throws(Kernel.Thread.Pool.Error) {
                _ = try await pool.run {
                    started.open()
                    release.wait()
                    return Kernel.Thread.Pool.Test.Resource(census)
                }
                return nil
            } catch {
                return error
            }
        }

        #expect(started.wait(timeout: .seconds(5)))
        request.cancel()
        #expect(finished.wait(timeout: .milliseconds(200)))
        #expect(await request.value == .cancelled)
        #expect(census.withLocked { $0 } == 0)

        release.open()
        pool.shutdown()
        #expect(census.withLocked { $0 } == 1)
    }

    @Test
    func `timeout uses the total budget including admission`() async {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        let firstStarted = Kernel.Thread.Gate()
        let firstRelease = Kernel.Thread.Gate()
        let secondStarted = Kernel.Thread.Gate()
        let secondRelease = Kernel.Thread.Gate()
        let secondFinished = Kernel.Thread.Gate()

        let first = Task { () -> Int? in
            do throws(Kernel.Thread.Pool.Error) {
                return try await pool.run {
                    firstStarted.open()
                    firstRelease.wait()
                    return 1
                }
            } catch {
                Issue.record("First operation failed: \(error)")
                return nil
            }
        }
        #expect(firstStarted.wait(timeout: .seconds(5)))

        let second = Task { () -> Kernel.Thread.Pool.Error? in
            defer { secondFinished.open() }
            do throws(Kernel.Thread.Pool.Error) {
                _ = try await pool.run(timeout: .milliseconds(600)) {
                    secondStarted.open()
                    secondRelease.wait()
                    return 2
                }
                return nil
            } catch {
                return error
            }
        }
        await Kernel.Thread.Pool.Test.Admission.wait(in: pool)
        let deadline = Task { try await Task.sleep(for: .milliseconds(300)) }
        if case .failure = await deadline.result {
            Issue.record("Deadline observation was cancelled")
        }
        firstRelease.open()
        #expect(secondStarted.wait(timeout: .seconds(5)))

        #expect(secondFinished.wait(timeout: .milliseconds(400)))
        #expect(await second.value == .timeout)
        secondRelease.open()
        let value = await first.value
        #expect(value == 1)
        pool.shutdown()
    }

    @Test
    func `timeout rejects queued work and releases its reservation`() async {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        let firstStarted = Kernel.Thread.Gate()
        let firstRelease = Kernel.Thread.Gate()
        let secondStarted = Kernel.Thread.Gate()
        let secondFinished = Kernel.Thread.Gate()

        let first = Task { () -> Int? in
            do throws(Kernel.Thread.Pool.Error) {
                return try await pool.run {
                    firstStarted.open()
                    firstRelease.wait()
                    return 1
                }
            } catch {
                Issue.record("First operation failed: \(error)")
                return nil
            }
        }
        #expect(firstStarted.wait(timeout: .seconds(5)))

        let second = Task { () -> Kernel.Thread.Pool.Error? in
            defer { secondFinished.open() }
            do throws(Kernel.Thread.Pool.Error) {
                _ = try await pool.run(timeout: .milliseconds(100)) {
                    secondStarted.open()
                    return 2
                }
                return nil
            } catch {
                return error
            }
        }
        await Kernel.Thread.Pool.Test.Admission.wait(in: pool)

        #expect(secondFinished.wait(timeout: .milliseconds(500)))
        #expect(await second.value == .timeout)
        #expect(!secondStarted.isOpen)

        let third = Task { () -> Int? in
            do throws(Kernel.Thread.Pool.Error) {
                return try await pool.run { 3 }
            } catch {
                Issue.record("Third operation failed: \(error)")
                return nil
            }
        }
        await Kernel.Thread.Pool.Test.Admission.wait(in: pool)
        firstRelease.open()

        let firstValue = await first.value
        let thirdValue = await third.value
        #expect(firstValue == 1)
        #expect(thirdValue == 3)
        pool.shutdown()
    }

    @Test
    func `cancellation rejects queued work and releases its reservation`() async {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        let firstStarted = Kernel.Thread.Gate()
        let firstRelease = Kernel.Thread.Gate()
        let secondStarted = Kernel.Thread.Gate()
        let secondFinished = Kernel.Thread.Gate()

        let first = Task { () -> Int? in
            do throws(Kernel.Thread.Pool.Error) {
                return try await pool.run {
                    firstStarted.open()
                    firstRelease.wait()
                    return 1
                }
            } catch {
                Issue.record("First operation failed: \(error)")
                return nil
            }
        }
        #expect(firstStarted.wait(timeout: .seconds(5)))

        let second = Task { () -> Kernel.Thread.Pool.Error? in
            defer { secondFinished.open() }
            do throws(Kernel.Thread.Pool.Error) {
                _ = try await pool.run {
                    secondStarted.open()
                    return 2
                }
                return nil
            } catch {
                return error
            }
        }
        await Kernel.Thread.Pool.Test.Admission.wait(in: pool)
        second.cancel()

        #expect(secondFinished.wait(timeout: .milliseconds(200)))
        #expect(await second.value == .cancelled)
        #expect(!secondStarted.isOpen)

        let third = Task { () -> Int? in
            do throws(Kernel.Thread.Pool.Error) {
                return try await pool.run { 3 }
            } catch {
                Issue.record("Third operation failed: \(error)")
                return nil
            }
        }
        await Kernel.Thread.Pool.Test.Admission.wait(in: pool)
        firstRelease.open()

        let firstValue = await first.value
        let thirdValue = await third.value
        #expect(firstValue == 1)
        #expect(thirdValue == 3)
        pool.shutdown()
    }

    @Test
    func `shutdown resumes admitted requester before draining physical work`() async {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(0)))
        )
        let started = Kernel.Thread.Gate()
        let release = Kernel.Thread.Gate()
        let requestFinished = Kernel.Thread.Gate()
        let shutdownFinished = Kernel.Thread.Gate()

        let request = Task { () -> Kernel.Thread.Pool.Error? in
            defer { requestFinished.open() }
            do throws(Kernel.Thread.Pool.Error) {
                _ = try await pool.run {
                    started.open()
                    release.wait()
                    return 1
                }
                return nil
            } catch {
                return error
            }
        }
        #expect(started.wait(timeout: .seconds(5)))

        let shutdown = Task.detached {
            pool.shutdown()
            shutdownFinished.open()
        }

        #expect(requestFinished.wait(timeout: .milliseconds(200)))
        #expect(await request.value == .shutdown)
        #expect(!shutdownFinished.wait(timeout: .milliseconds(200)))

        release.open()
        #expect(shutdownFinished.wait(timeout: .seconds(5)))
        await shutdown.value
    }

    @Test
    func `shutdown rejects queued work without executing it`() async {
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        let firstStarted = Kernel.Thread.Gate()
        let firstRelease = Kernel.Thread.Gate()
        let firstFinished = Kernel.Thread.Gate()
        let secondStarted = Kernel.Thread.Gate()
        let secondFinished = Kernel.Thread.Gate()
        let shutdownFinished = Kernel.Thread.Gate()

        let first = Task { () -> Kernel.Thread.Pool.Error? in
            defer { firstFinished.open() }
            do throws(Kernel.Thread.Pool.Error) {
                _ = try await pool.run {
                    firstStarted.open()
                    firstRelease.wait()
                    return 1
                }
                return nil
            } catch {
                return error
            }
        }
        #expect(firstStarted.wait(timeout: .seconds(5)))

        let second = Task { () -> Kernel.Thread.Pool.Error? in
            defer { secondFinished.open() }
            do throws(Kernel.Thread.Pool.Error) {
                _ = try await pool.run {
                    secondStarted.open()
                    return 2
                }
                return nil
            } catch {
                return error
            }
        }
        await Kernel.Thread.Pool.Test.Admission.wait(in: pool)

        let shutdown = Task.detached {
            pool.shutdown()
            shutdownFinished.open()
        }

        #expect(firstFinished.wait(timeout: .milliseconds(200)))
        #expect(secondFinished.wait(timeout: .milliseconds(200)))
        #expect(await first.value == .shutdown)
        #expect(await second.value == .shutdown)
        #expect(!secondStarted.isOpen)
        #expect(!shutdownFinished.wait(timeout: .milliseconds(200)))

        firstRelease.open()
        #expect(shutdownFinished.wait(timeout: .seconds(5)))
        await shutdown.value
    }
}

extension Kernel.Thread.Pool.Test.Integration {
    @Test
    func `run returns a value`() async throws(Kernel.Thread.Pool.Error) {
        let pool = Kernel.Thread.Pool(.init(workers: .init(2)))
        defer { pool.shutdown() }

        #expect(try await pool.run { 42 } == 42)
    }

    @Test
    func `run transfers a move-only result`() async throws(Kernel.Thread.Pool.Error) {
        let pool = Kernel.Thread.Pool(.init(workers: .init(1)))
        let census = KernelThreadTest.Harness(0)

        do {
            let resource = try await pool.run {
                Kernel.Thread.Pool.Test.Resource(census)
            }
            #expect(census.withLocked { $0 } == 0)
            #expect(resource.census === census)
        }

        #expect(census.withLocked { $0 } == 1)
        pool.shutdown()
    }

    @Test
    func `throwing run transfers a move-only success`() async throws(
        Either<Kernel.Thread.Pool.Error, Kernel.Thread.Pool.Test.Failure>
    ) {
        let pool = Kernel.Thread.Pool(.init(workers: .init(1)))
        let census = KernelThreadTest.Harness(0)

        do {
            let resource = try await pool.run {
                () throws(Kernel.Thread.Pool.Test.Failure) -> Kernel.Thread.Pool.Test.Resource in
                Kernel.Thread.Pool.Test.Resource(census)
            }
            #expect(census.withLocked { $0 } == 0)
            #expect(resource.census === census)
        }

        #expect(census.withLocked { $0 } == 1)
        pool.shutdown()
    }
}

extension Kernel.Thread.Pool.Test.Admission {
    static func wait(
        in pool: Kernel.Thread.Pool
    ) async {
        for _ in 0..<500 {
            if pool.admission.metrics.currentWaiters == 1 {
                return
            }
            let interval = Task { try await Task.sleep(for: .milliseconds(10)) }
            if case .failure = await interval.result {
                Issue.record("Admission observation was cancelled")
                return
            }
        }
        Issue.record("Expected one operation waiting for admission")
    }
}
