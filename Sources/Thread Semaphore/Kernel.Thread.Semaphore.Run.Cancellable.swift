extension Kernel.Thread.Semaphore.Run {

    public struct Cancellable: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        let token: Kernel.Thread.Semaphore.Cancellation

        @usableFromInline
        var interval: Duration

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore, token: Kernel.Thread.Semaphore.Cancellation) {
            self.semaphore = semaphore
            self.token = token
            self.interval = .milliseconds(10)
        }
    }

    public func cancellable(_ token: Kernel.Thread.Semaphore.Cancellation) -> Cancellable {
        Cancellable(semaphore: semaphore, token: token)
    }
}

extension Kernel.Thread.Semaphore.Run.Cancellable {
    @usableFromInline
    static let minimum: Duration = .milliseconds(1)

    public func poll(_ interval: Duration) -> Self {
        var copy = self
        copy.interval = max(interval, Self.minimum)
        return copy
    }

    @inlinable
    public func callAsFunction<T: Sendable>(
        _ body: @Sendable () -> T
    ) throws(Kernel.Thread.Semaphore.Error) -> T {
        try semaphore._acquire(cancellation: token, poll: interval)
        defer { semaphore._release() }

        let result = body()

        if token.isCancelled {
            throw .cancelled
        }
        return result
    }
}
