//
//  Kernel.Thread.Pool+Run.swift
//  swift-threads
//

internal import Async_Semaphore_Primitives
public import Either_Primitives
internal import Ownership_Latch_Primitives

extension Kernel.Thread.Pool {
    /// Executes a non-throwing operation on a dedicated worker thread.
    ///
    /// - Parameters:
    ///   - timeout: The total budget for admission and execution.
    ///   - operation: The operation to execute.
    /// - Returns: The operation's result.
    /// - Throws: A bounded-admission or logical-delivery error.
    ///
    /// Cancellation, timeout, and shutdown abandon logical delivery only.
    /// An admitted worker remains the physical owner of the operation and any
    /// late result until both have been destroyed.
    nonisolated(nonsending)
        public func run<T: ~Copyable>(
            timeout: Duration? = nil,
            _ operation: sending @escaping () -> T
        ) async throws(Kernel.Thread.Pool.Error) -> sending T
    {
        let started = ContinuousClock.now
        try lifecycle.reserve()
        let result = Ownership.Latch<T>()
        let work = Ownership.Latch(operation)
        let timer = Ownership.Latch<Task<Void, any Swift.Error>>()
        let dispatch = Ownership.Latch<Task<Void, Never>>()
        let id = ObjectIdentifier(result)

        let failure: Kernel.Thread.Pool.Error? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard lifecycle.register(id, continuation: continuation) else {
                    continuation.resume(returning: .shutdown)
                    lifecycle.release()
                    return
                }

                if let timeout {
                    let elapsed = started.duration(to: .now)
                    let remaining = elapsed < timeout ? timeout - elapsed : .zero
                    timer.store(deadline(after: remaining, for: id))
                }

                dispatch.store(
                    Task {
                        do throws(Async.Semaphore.Error) {
                            try await admission.wait()
                        } catch {
                            lifecycle.resolve(id)?.resume(
                                returning: Kernel.Thread.Pool.Error(from: error)
                            )
                            lifecycle.release()
                            return
                        }

                        if !lifecycle.admit(id) || Task.isCancelled {
                            admission.signal()
                            lifecycle.release()
                            return
                        }

                        let executor = executors.next()
                        Task<Void, Never>(executorPreference: executor) {
                            guard let operation = work.take() else {
                                preconditionFailure("Thread-pool operation was already taken")
                            }
                            result.store(operation())
                            lifecycle.resolve(id)?.resume(returning: nil)
                            admission.signal()
                            lifecycle.release()
                        }
                    }
                )

                if Task.isCancelled {
                    lifecycle.resolve(id)?.resume(returning: .cancelled)
                }
            }
        } onCancel: {
            lifecycle.resolve(id)?.resume(returning: .cancelled)
        }

        if let task = timer.take() {
            task.cancel()
            _ = await task.result
        }
        if let task = dispatch.take() {
            task.cancel()
            await task.value
        }

        if let failure {
            throw failure
        }
        guard let result = result.take() else {
            preconditionFailure("Thread-pool completion did not publish a result")
        }
        return result
    }

    /// Executes a throwing operation on a dedicated worker thread.
    ///
    /// - Parameters:
    ///   - timeout: The total budget for admission and execution.
    ///   - operation: The operation to execute.
    /// - Returns: The operation's result.
    /// - Throws: The left side for pool lifecycle failures and the right side
    ///   for an operation failure.
    ///
    /// Cancellation, timeout, and shutdown abandon logical delivery only.
    /// An admitted worker remains the physical owner of the operation and any
    /// late result until both have been destroyed.
    nonisolated(nonsending)
        public func run<T: ~Copyable, E: Swift.Error>(
            timeout: Duration? = nil,
            _ operation: sending @escaping () throws(E) -> T
        ) async throws(Either<Kernel.Thread.Pool.Error, E>) -> sending T
    {
        let started = ContinuousClock.now
        do throws(Kernel.Thread.Pool.Error) {
            try lifecycle.reserve()
        } catch {
            throw .left(error)
        }
        let outcome = Ownership.Latch<Kernel.Thread.Pool.Outcome<T, E>>()
        let work = Ownership.Latch(operation)
        let timer = Ownership.Latch<Task<Void, any Swift.Error>>()
        let dispatch = Ownership.Latch<Task<Void, Never>>()
        let id = ObjectIdentifier(outcome)

        let failure: Kernel.Thread.Pool.Error? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard lifecycle.register(id, continuation: continuation) else {
                    continuation.resume(returning: .shutdown)
                    lifecycle.release()
                    return
                }

                if let timeout {
                    let elapsed = started.duration(to: .now)
                    let remaining = elapsed < timeout ? timeout - elapsed : .zero
                    timer.store(deadline(after: remaining, for: id))
                }

                dispatch.store(
                    Task {
                        do throws(Async.Semaphore.Error) {
                            try await admission.wait()
                        } catch {
                            lifecycle.resolve(id)?.resume(
                                returning: Kernel.Thread.Pool.Error(from: error)
                            )
                            lifecycle.release()
                            return
                        }

                        if !lifecycle.admit(id) || Task.isCancelled {
                            admission.signal()
                            lifecycle.release()
                            return
                        }

                        let executor = executors.next()
                        Task<Void, Never>(executorPreference: executor) {
                            guard let operation = work.take() else {
                                preconditionFailure("Thread-pool operation was already taken")
                            }
                            do throws(E) {
                                outcome.store(.success(try operation()))
                            } catch {
                                outcome.store(.failure(error))
                            }
                            lifecycle.resolve(id)?.resume(returning: nil)
                            admission.signal()
                            lifecycle.release()
                        }
                    }
                )

                if Task.isCancelled {
                    lifecycle.resolve(id)?.resume(returning: .cancelled)
                }
            }
        } onCancel: {
            lifecycle.resolve(id)?.resume(returning: .cancelled)
        }

        if let task = timer.take() {
            task.cancel()
            _ = await task.result
        }
        if let task = dispatch.take() {
            task.cancel()
            await task.value
        }

        if let failure {
            throw .left(failure)
        }
        guard let outcome = outcome.take() else {
            preconditionFailure("Thread-pool completion did not publish an outcome")
        }
        switch consume outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw .right(error)
        }
    }

    /// Schedules abandonment of one registered delivery at its deadline.
    ///
    /// The timer uses the standard task failure channel: cancellation aborts
    /// the sleep and abandons timeout delivery. Callers cancel and join the
    /// task through its nonthrowing `result`.
    private func deadline(
        after remaining: Duration,
        for id: ObjectIdentifier
    ) -> Task<Void, any Swift.Error> {
        Task.detached { [lifecycle] in
            try await Task.sleep(for: remaining)
            lifecycle.resolve(id)?.resume(returning: .timeout)
        }
    }
}
