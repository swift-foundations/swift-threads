extension Kernel.Thread.Semaphore {

    public struct Shutdown: Sendable {
        @usableFromInline
        let semaphore: Kernel.Thread.Semaphore

        @usableFromInline
        init(semaphore: Kernel.Thread.Semaphore) {
            self.semaphore = semaphore
        }
    }
}

extension Kernel.Thread.Semaphore {

    public var shutdown: Shutdown { Shutdown(semaphore: self) }
}

extension Kernel.Thread.Semaphore.Shutdown {

    public func callAsFunction() {
        semaphore._shutdown()
    }

    public func wait() {
        semaphore._wait()
    }
}
