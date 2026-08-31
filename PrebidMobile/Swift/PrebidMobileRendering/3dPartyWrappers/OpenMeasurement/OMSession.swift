//
// Copyright 2018-2025 Prebid.org, Inc.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import UIKit

@objc(PBMOMSession)
public protocol OMSession: NSObjectProtocol {
    
    var eventTracker: EventTrackerProtocol { get }

    func start()

    /// Finishes the session. The rendering path relies on the session being deallocated to do this, but a
    /// caller that outlives the ad view — such as a native ad whose registered view is swapped out — has to
    /// end it explicitly so the verification script is told the ad is gone.
    func stop()

    func addFriendlyObstruction(_ friendlyObstruction: UIView,
                                purpose: OpenMeasurementFriendlyObstructionPurpose)
}
