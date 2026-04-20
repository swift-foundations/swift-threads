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

import Testing
import Kernel
import Thread_Semaphore
import Thread_Gate

@Suite("Kernel.Thread.Semaphore")
struct KernelThreadSemaphoreTests {

    @Suite("Unit")
    struct Unit {

        @Test
        func `acquire succeeds when capacity available`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 2)

            let result = try semaphore.run { 42 }

            #expect(result == 42)
            #expect(semaphore.metrics.acquisitions == 1)
            #expect(semaphore.metrics.releases == 1)
        }

        @Test
        func `multiple acquires within capacity`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 3)

            let gate1 = Kernel.Thread.Gate()
            let gate2 = Kernel.Thread.Gate()
            let gate3 = Kernel.Thread.Gate()
            let releaseGate = Kernel.Thread.Gate()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    gate1.open()
                    releaseGate.wait()
                }
            }
            let t2 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    gate2.open()
                    releaseGate.wait()
                }
            }
            let t3 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    gate3.open()
                    releaseGate.wait()
                }
            }

            gate1.wait()
            gate2.wait()
            gate3.wait()

            #expect(semaphore.metrics.outstanding == 3)

            releaseGate.open()
            t1.join()
            t2.join()
            t3.join()
        }

        @Test
        func `permit conservation`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 5)

            for _ in 0..<100 {
                _ = try semaphore.run { }
            }

            let m = semaphore.metrics
            #expect(m.available + m.outstanding == 5)
            #expect(m.acquisitions == 100)
            #expect(m.releases == 100)
        }

        @Test
        func `throwing body returns Result`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)

            struct TestError: Swift.Error {}

            let result: Result<Int, TestError> = try semaphore.run { () throws(TestError) -> Int in
                throw TestError()
            }

            switch result {
            case .success:
                Issue.record("Expected failure")
            case .failure:
                break
            }
        }
    }

    @Suite("Blocking")
    struct Blocking {

        @Test
        func `acquire blocks when exhausted then succeeds on release`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)
            let firstAcquired = Kernel.Thread.Gate()
            let allowRelease = Kernel.Thread.Gate()
            let secondAcquired = Kernel.Thread.Gate()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    firstAcquired.open()
                    allowRelease.wait()
                }
            }

            firstAcquired.wait()
            #expect(semaphore.metrics.outstanding == 1)
            #expect(semaphore.metrics.available == 0)

            let t2 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    secondAcquired.open()
                }
            }

            #expect(!secondAcquired.wait(timeout: .milliseconds(50)))
            #expect(semaphore.metrics.waiters > 0)

            allowRelease.open()

            #expect(secondAcquired.wait(timeout: .seconds(1)))
            #expect(semaphore.metrics.acquisitions == 2)

            t1.join()
            t2.join()
        }
    }

    @Suite("Timeout")
    struct Timeout {

        @Test
        func `timeout returns nil after duration`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)
            let holding = Kernel.Thread.Gate()
            let released = Kernel.Thread.Gate()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    holding.open()
                    released.wait()
                }
            }

            holding.wait()

            let timeout = semaphore.run.timeout(.milliseconds(50))
            let result = try timeout { 42 }

            #expect(result == nil)
            #expect(semaphore.metrics.timeouts == 1)

            released.open()
            t1.join()
        }

        @Test
        func `acquisition succeeds if permit available at deadline`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)

            let timeout = semaphore.run.timeout(.milliseconds(100))
            let result = try timeout { 42 }

            #expect(result == 42)
        }
    }

    @Suite("Shutdown")
    struct Shutdown {

        @Test
        func `shutdown rejects new runs`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)

            semaphore.shutdown()

            #expect(throws: Kernel.Thread.Semaphore.Error.shutdown) {
                try semaphore.run { 42 }
            }

            #expect(semaphore.metrics.rejected == 1)
        }

        @Test
        func `shutdown.wait returns when outstanding reaches zero`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)
            let acquired = Kernel.Thread.Gate()
            let canRelease = Kernel.Thread.Gate()
            let shutdownComplete = Kernel.Thread.Gate()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    acquired.open()
                    canRelease.wait()
                }
            }

            acquired.wait()

            let t2 = try Kernel.Thread.spawn {
                semaphore.shutdown.wait()
                shutdownComplete.open()
            }

            #expect(!shutdownComplete.wait(timeout: .milliseconds(50)))

            canRelease.open()

            #expect(shutdownComplete.wait(timeout: .seconds(1)))

            t1.join()
            t2.join()
        }

        @Test
        func `shutdown wakes blocked waiters`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)
            let acquired = Kernel.Thread.Gate()
            let waiterDone = Kernel.Thread.Gate()
            let holdingRelease = Kernel.Thread.Gate()

            final class Box: @unchecked Sendable { var gotShutdown = false }
            let box = Box()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    acquired.open()
                    holdingRelease.wait()
                }
            }

            acquired.wait()

            let t2 = try Kernel.Thread.spawn {
                do {
                    _ = try semaphore.run { }
                } catch Kernel.Thread.Semaphore.Error.shutdown {
                    box.gotShutdown = true
                } catch {
                    // Other error
                }
                waiterDone.open()
            }

            #expect(!waiterDone.wait(timeout: .milliseconds(50)))

            semaphore.shutdown()

            #expect(waiterDone.wait(timeout: .seconds(1)))
            #expect(box.gotShutdown)

            holdingRelease.open()

            t1.join()
            t2.join()
        }
    }

    @Suite("Cancellation")
    struct Cancellation {

        @Test
        func `cancellation while waiting returns cancelled`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)
            let token = Kernel.Thread.Semaphore.Cancellation()
            let acquired = Kernel.Thread.Gate()
            let waiterDone = Kernel.Thread.Gate()
            let holdingRelease = Kernel.Thread.Gate()

            final class Box: @unchecked Sendable { var gotCancelled = false }
            let box = Box()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    acquired.open()
                    holdingRelease.wait()
                }
            }

            acquired.wait()

            let t2 = try Kernel.Thread.spawn {
                do {
                    let cancellable = semaphore.run.cancellable(token).poll(.milliseconds(5))
                    _ = try cancellable { }
                } catch Kernel.Thread.Semaphore.Error.cancelled {
                    box.gotCancelled = true
                } catch {
                    // Other error
                }
                waiterDone.open()
            }

            #expect(!waiterDone.wait(timeout: .milliseconds(50)))

            token.cancel()

            #expect(waiterDone.wait(timeout: .seconds(1)))
            #expect(box.gotCancelled)
            #expect(semaphore.metrics.cancellations == 1)

            holdingRelease.open()

            t1.join()
            t2.join()
        }

        @Test
        func `cancellation after body returns cancelled`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)
            let token = Kernel.Thread.Semaphore.Cancellation()

            token.cancel()

            let cancellable = semaphore.run.cancellable(token)
            #expect(throws: Kernel.Thread.Semaphore.Error.cancelled) {
                _ = try cancellable {
                    42
                }
            }
        }

        @Test
        func `shutdown dominates cancellation`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 1)
            let token = Kernel.Thread.Semaphore.Cancellation()
            let acquired = Kernel.Thread.Gate()
            let waiterDone = Kernel.Thread.Gate()
            let holdingRelease = Kernel.Thread.Gate()

            final class Box: @unchecked Sendable { var error: Kernel.Thread.Semaphore.Error? }
            let box = Box()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    acquired.open()
                    holdingRelease.wait()
                }
            }

            acquired.wait()

            let t2 = try Kernel.Thread.spawn {
                do {
                    let cancellable = semaphore.run.cancellable(token).poll(.milliseconds(5))
                    _ = try cancellable { }
                } catch let e as Kernel.Thread.Semaphore.Error {
                    box.error = e
                } catch {
                    // Other error
                }
                waiterDone.open()
            }

            #expect(!waiterDone.wait(timeout: .milliseconds(50)))

            token.cancel()
            semaphore.shutdown()

            #expect(waiterDone.wait(timeout: .seconds(1)))
            #expect(box.error == .shutdown)

            holdingRelease.open()

            t1.join()
            t2.join()
        }
    }

    @Suite("Metrics")
    struct MetricsSuite {

        @Test
        func `metrics track acquisitions and releases`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 3)

            for _ in 0..<10 {
                _ = try semaphore.run { }
            }

            let m = semaphore.metrics
            #expect(m.acquisitions == 10)
            #expect(m.releases == 10)
            #expect(m.outstanding == 0)
            #expect(m.available == 3)
        }

        @Test
        func `peak tracks maximum outstanding`() throws {
            let semaphore = Kernel.Thread.Semaphore(capacity: 3)
            let gate1 = Kernel.Thread.Gate()
            let gate2 = Kernel.Thread.Gate()
            let release = Kernel.Thread.Gate()

            let t1 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    gate1.open()
                    release.wait()
                }
            }
            let t2 = try Kernel.Thread.spawn {
                _ = try? semaphore.run {
                    gate2.open()
                    release.wait()
                }
            }

            gate1.wait()
            gate2.wait()

            #expect(semaphore.metrics.peak >= 2)

            release.open()

            t1.join()
            t2.join()

            #expect(semaphore.metrics.peak >= 2)
        }
    }
}
