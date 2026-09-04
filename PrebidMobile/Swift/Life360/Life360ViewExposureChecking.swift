
import Foundation
import UIKit

/// Mirrors the initializer of the Objective-C `Life360ViewExposureChecker`.
/// This is necessary because the Objc target depends on the Swift target and not the reverse, so Swift
/// code cannot import that class directly — it has to look it up by name and cast it to a protocol the
/// class conforms to (see `Factory.life360ViewExposureCheckerType`).
@objc(Life360ViewExposureChecking) @_spi(PBMInternal) public
protocol Life360ViewExposureChecking: NSObjectProtocol {
    init(view: UIView, onExposureChange: ((ViewExposure, Error?) -> Void)?)

    /// Views overlapping the ad that draw no opaque content. Open Measurement needs these declared as
    /// friendly obstructions or it counts them against the ad's viewable area.
    func friendlyObstructionViews() -> [UIView]
}
