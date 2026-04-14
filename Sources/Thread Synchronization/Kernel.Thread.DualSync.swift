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

extension Kernel.Thread {
    /// Dual condition variable synchronization.
    ///
    /// Use for patterns requiring separate signaling channels,
    /// e.g., worker/deadline separation in blocking lane implementations.
    public typealias DualSync = Synchronization<2>
}
