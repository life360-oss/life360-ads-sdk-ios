// Life360Bid+AdType.swift

import Foundation

public extension Bid {
    var life360AdType: Life360AdType? {
        bid.ext?.life360?.life360AdType
    }

    /// Whether Life360's renderer expands this creative to fill its container instead of leaving it at the
    /// fixed bid size a standard banner uses.
    var usesLife360Rendering: Bool {
        if let life360AdType {
            // Standard display is the one Life360 type that renders as an ordinary fixed-size banner.
            return life360AdType != .standardDisplay
        }
        return adm?.range(of: "load.js", options: .caseInsensitive) != nil
    }
}
