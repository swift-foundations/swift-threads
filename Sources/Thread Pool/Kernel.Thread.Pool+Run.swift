//
//  Kernel.Thread.Pool+Run.swift
//  swift-executors
//

internal import Async_Semaphore_Primitives
public import Either_Primitives

extension Kernel.Thread.Pool {
    /// Execute a non-throwing operation on a dedicated worker thread.
    ///
    /// 1. Acquires admission (async-suspending semaphore)
    /// 2. Dispatches to a worker executor via `Task(executorPreference:)`
    /// 3. Returns the result via continuation's `sending` semantics —
    ///    no `T: Sendable` requirement.
    nonisolated(nonsending)
        public func run<T>(
            timeout: Duration? = nil,
            _ operation: sending @escaping () -> T
        ) async throws(Self.Error) -> sending T
    {
        inFlight.enter()
        defer { inFlight.leave() }

        do throws(Async.Semaphore.Error) {
            if let timeout {
                try await admission.wait(timeout: timeout)
            } else {
                try await admission.wait()
            }
        } catch {
            throw Self.Error(from: error)
        }

        defer { admission.signal() }

        let executor = executors.next()
        nonisolated(unsafe) let op = operation
        return await withCheckedContinuation { continuation in
            Task<Void, Never>(executorPreference: executor) {
                unsafe continuation.resume(returning: op())
            }
        }
    }

    /// Execute a throwing operation on a dedicated worker thread.
    ///
    /// The outer `Either<Pool.Error, E>` distinguishes admission failures
    /// (cancelled/timeout/shutdown) from operation failures.
    nonisolated(nonsending)
        public func run<T, E: Swift.Error>(
            timeout: Duration? = nil,
            _ operation: sending @escaping () throws(E) -> T
        ) async throws(Either<Kernel.Thread.Pool.Error, E>) -> sending T
    {
        inFlight.enter()
        defer { inFlight.leave() }

        do throws(Async.Semaphore.Error) {
            if let timeout {
                try await admission.wait(timeout: timeout)
            } else {
                try await admission.wait()
            }
        } catch {
            throw .left(Self.Error(from: error))
        }

        defer { admission.signal() }

        let executor = executors.next()
        nonisolated(unsafe) let op = operation
        let result: Result<T, E> = await withCheckedContinuation { continuation in
            Task<Void, Never>(executorPreference: executor) {
                do throws(E) {
                    let value = unsafe try op()
                    continuation.resume(returning: .success(value))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }

        switch result {
        case .success(let value): return value
        case .failure(let error): throw .right(error)
        }
    }
}
