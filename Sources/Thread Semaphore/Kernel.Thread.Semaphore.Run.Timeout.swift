extension Kernel.Thread.Semaphore.Run {

    public struct Timeout: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        let duration: Duration

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore, duration: Duration) {
            self.semaphore = semaphore
            self.duration = duration
        }
    }

    public func timeout(_ duration: Duration) -> Timeout {
        Timeout(semaphore: semaphore, duration: duration)
    }
}

extension Kernel.Thread.Semaphore.Run.Timeout {

    @inlinable
    public func callAsFunction<T: Sendable>(
        _ body: @Sendable () -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> T? {
        guard try semaphore._acquire(timeout: duration) else {
            return nil
        }
        defer { semaphore._release() }
        return body()
    }
}
