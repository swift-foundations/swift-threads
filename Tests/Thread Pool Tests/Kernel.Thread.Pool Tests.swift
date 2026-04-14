//
//  Kernel.Thread.Pool Tests.swift
//  swift-threads
//

import Testing

@testable import Thread_Pool
import Kernel_Test_Support

extension Kernel.Thread.Pool {
    enum Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Kernel.Thread.Pool.Test.Unit {
    @Test("shared pool exists")
    func sharedExists() {
        _ = Kernel.Thread.Pool.shared
    }

    @Test("custom pool with options")
    func customOptions() {
        let pool = Kernel.Thread.Pool(.init(workers: try! .init(2), admissionLimit: 8))
        pool.shutdown()
    }
}

// MARK: - Edge Case Tests

extension Kernel.Thread.Pool.Test.EdgeCase {
    @Test("shutdown rejects new work")
    func shutdownRejects() async {
        let pool = Kernel.Thread.Pool(.init(workers: try! .init(1), admissionLimit: 4))
        pool.shutdown()

        do {
            _ = try await pool.run { 1 }
            Issue.record("Expected shutdown error")
        } catch {
            #expect(error == .shutdown)
        }
    }

    @Test("throwing operation propagates as .right")
    func throwingPropagates() async {
        struct TestError: Swift.Error, Sendable, Equatable {}
        let pool = Kernel.Thread.Pool(.init(workers: try! .init(1), admissionLimit: 4))
        defer { pool.shutdown() }

        do {
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
    @Test("run completes and returns value")
    func runReturnsValue() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try! .init(2), admissionLimit: 8))
        defer { pool.shutdown() }

        let result = try await pool.run { 42 }
        #expect(result == 42)
    }

    @Test("multiple runs complete independently")
    func multipleRuns() async throws {
        let pool = Kernel.Thread.Pool(.init(workers: try! .init(2), admissionLimit: 8))
        defer { pool.shutdown() }

        let r1 = try await pool.run { 1 }
        let r2 = try await pool.run { 2 }
        let r3 = try await pool.run { 3 }
        #expect(r1 == 1)
        #expect(r2 == 2)
        #expect(r3 == 3)
    }

    @Test("non-Sendable return via async run")
    func nonSendableReturn() async throws {
        final class Box { var value: Int; init(_ v: Int) { self.value = v } }
        let pool = Kernel.Thread.Pool(.init(workers: try! .init(1), admissionLimit: 4))
        defer { pool.shutdown() }

        let box: Box = try await pool.run { Box(99) }
        #expect(box.value == 99)
    }
}
