extension Kernel.Thread.Pool {

    enum Outcome<Success: ~Copyable, Failure: Swift.Error>: ~Copyable {
        case success(Success)
        case failure(Failure)
    }
}
