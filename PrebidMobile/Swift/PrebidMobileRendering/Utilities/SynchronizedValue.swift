//
// Copyright 2018-2026 Prebid.org, Inc.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

/// Lock-guarded storage for a single value.
///
/// Exists so process-wide configuration can be read while an ad request is in flight without the
/// reader seeing a partially-written value. Concurrent access to a plain Swift `Dictionary` or `Array`
/// while another thread writes it is memory-unsafe, not merely stale.
///
/// Deliberately not `@objc`-exposed: it is used as private backing storage behind existing `@objc`
/// computed properties, so the Obj-C surface of the types adopting it is unchanged.
///
/// `NSLock` rather than `os_unfair_lock`, because the closures below run arbitrary caller code and
/// unfair locks are unsafe to hold across ARC traffic.
final class SynchronizedValue<Value> {

    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    /// Atomic get and atomic set. Not atomic as a read-modify-write — use `mutate` for that.
    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    /// Reads the value in place. Use for collections, so a caller can inspect or copy without the
    /// value changing underneath it.
    ///
    /// - Warning: never call another member of the same box from inside `body`; this lock is not
    ///   recursive and doing so deadlocks.
    func withValue<R>(_ body: (Value) throws -> R) rethrows -> R {
        try lock.withLock { try body(storage) }
    }

    /// Atomic read-modify-write, for the check-then-act cases a plain setter cannot express.
    ///
    /// - Warning: same non-recursive restriction as `withValue`.
    func mutate<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        try lock.withLock { try body(&storage) }
    }
}
