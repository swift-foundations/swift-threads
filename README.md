# swift-threads

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Thread-layer compositions for Swift. Houses composed types that build on `Kernel.Thread` primitives but are neither raw syscall wrappers (that's swift-kernel) nor Swift Executor protocol conformances (that's swift-executors). Layer 3 (Foundations) of the Swift Institute five-layer architecture.

---

## Package mission

- **swift-kernel** (L3): thin syscall-adjacent wrappers over L1 primitives
- **swift-executors** (L3): types that ARE Swift Executors (`SerialExecutor`, `TaskExecutor`)
- **swift-threads** (L3, this package): thread-layer compositions — admission, coordination, worker patterns

---

## Products (today)

| Product | Contents |
|---------|----------|
| `Thread Pool` | `Kernel.Thread.Pool` — admission-gated closure dispatch over `Kernel.Thread.Executor.Sharded` |

| Product | Contents |
|---------|----------|
| `Thread Barrier` | `Kernel.Thread.Barrier` (rendezvous coordination over `Synchronizer.Blocking<1>`) |
| `Thread Gate` | `Kernel.Thread.Gate` (one-shot rendezvous over `Synchronizer.Blocking<1>`) |
| `Thread Semaphore` | `Kernel.Thread.Semaphore` (thread-blocking counting semaphore over `Synchronizer.Blocking<2>`; distinct from `Async.Semaphore`) |
| `Thread Worker` | `Kernel.Thread.Worker` + `Token` |
| `Thread Actor` | `Kernel.Thread.Actor` (executor-backed actor) |
| `Threads` | umbrella re-exporting all of the above |

The underlying synchronization substrate (`Synchronizer.Blocking<N>` — mutex + N condvars) lives in the sibling [`swift-synchronizers`](../swift-synchronizers) L3 package. swift-threads consumes it directly via the `Synchronizer Blocking` product.

---

## Installation

### Package.swift

```swift
.package(path: "../swift-threads")
```

### Target dependency

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Thread Pool", package: "swift-threads")
    ]
)
```

Consumers should prefer narrow product imports — `Thread Pool`, `Thread Semaphore`, etc. — over the umbrella `Threads` unless they genuinely need the full stack.

### Requirements

- Swift 6.3+
- macOS 26.0+ / iOS 26.0+ / tvOS 26.0+ / watchOS 26.0+
- Linux (Ubuntu 22.04+)
- Windows (Swift 6.3+)

---

## Quick Start — Thread Pool

```swift
import Thread_Pool

let pool = Kernel.Thread.Pool()
defer { pool.shutdown() }

let result = try await pool.run { blockingSyscall() }
```

---

## Architecture

```
swift-threads       ← thread-layer compositions (this package)
     |
swift-executors     ← Swift Executor conformances
     |
swift-kernel        ← syscall-adjacent wrappers
     |
swift-kernel-primitives  ← raw syscall atoms
```

---

## License

Apache 2.0 — See [LICENSE](LICENSE.md) for details.
