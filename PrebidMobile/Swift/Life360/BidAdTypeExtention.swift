// Life360Bid+AdType.swift

import Foundation

public extension Bid {

    @objc var life360AdType: Life360AdType {
        bid.ext?.nativo?.adType ?? .unknown
    }

    /// Whether Life360's renderer expands this creative to fill its container instead of leaving it at the
    /// fixed bid size a standard banner uses.
    var usesLife360Rendering: Bool {
        if life360AdType != .unknown {
            // Standard display is the one Life360 type that renders as an ordinary fixed-size banner.
            return life360AdType != .standardDisplay
        }
        return adm?.range(of: "load.js", options: .caseInsensitive) != nil
    }
}
