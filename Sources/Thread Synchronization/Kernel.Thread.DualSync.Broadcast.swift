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

extension Kernel.Thread.DualSync {
    /// Accessor for broadcasting all conditions.
    public struct Broadcast: Sendable {
        private let sync: Kernel.Thread.DualSync

        init(sync: Kernel.Thread.DualSync) {
            self.sync = sync
        }

        /// Broadcast all conditions.
        public func all() {
            sync.broadcastAll()
        }
    }

    /// Broadcast all conditions accessor.
    public var broadcast: Broadcast {
        Broadcast(sync: self)
    }
}
