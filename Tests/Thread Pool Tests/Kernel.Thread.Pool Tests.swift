//
//  Kernel.Thread.Pool Tests.swift
//  swift-threads
//

import Kernel_Test_Support
import Testing

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
