// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-kernel open source project
//
// Copyright (c) 2024-2025 Coen ten Thije Boonkkamp and the swift-kernel project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Synchronization

extension Kernel.Thread.Semaphore.Cancellation {
    @usableFromInline
    final class Storage: Sendable {
        @usableFromInline
        let flag: Atomic<Bool>

        @usableFromInline
        init() {
            self.flag = Atomic(false)
        }
    }
}
