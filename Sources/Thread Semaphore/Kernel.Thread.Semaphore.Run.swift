extension Kernel.Thread.Semaphore {

    public struct Run: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore) {
            self.semaphore = semaphore
        }
    }
}

extension Kernel.Thread.Semaphore {

    public var run: Run { Run(semaphore: self) }
}

extension Kernel.Thread.Semaphore.Run {

    @inlinable
    public func callAsFunction<T: Sendable>(
        _ body: @Sendable () -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> T {
        try semaphore._acquire()
        defer { semaphore._release() }
        return body()
    }

    @inlinable
    public func callAsFunction<T: Sendable, E: Swift.Error>(
        _ body: @Sendable () throws(E) -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> Result<T, E> {
        try semaphore._acquire()
        defer { semaphore._release() }
        do throws(E) {
            return .success(try body())
        } catch {
            return .failure(error)
        }
    }
}
