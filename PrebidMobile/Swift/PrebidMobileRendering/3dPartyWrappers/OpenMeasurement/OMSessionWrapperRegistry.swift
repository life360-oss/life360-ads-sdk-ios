//
// Copyright 2018-2025 Prebid.org, Inc.

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

/// Hands the Objective-C measurement wrapper to Swift call sites.
///
/// This is necessary because the Objc target depends on the Swift target and not the reverse, so Swift
/// cannot name `PBMOpenMeasurementWrapper` at all. The rendering path sidesteps this by having
/// Objective-C inject the wrapper into the transaction it creates, but the original-API native path
/// starts in Swift with nothing to inject it — so the wrapper registers itself here instead.
@objc(PBMOMSessionWrapperRegistry)
public final class OMSessionWrapperRegistry: NSObject {

    private static let lock = NSLock()

    private static var _wrapper: OMSessionWrapper?

    /// `nil` if Open Measurement never came up, in which case callers should skip measurement rather
    /// than treat it as fatal.
    @objc public static var wrapper: OMSessionWrapper? {
        lock.withLock { _wrapper }
    }

    @objc public static func register(_ wrapper: OMSessionWrapper) {
        lock.withLock { _wrapper = wrapper }
    }

    private override init() {
        super.init()
    }
}
