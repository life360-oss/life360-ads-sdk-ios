// NativoBid+AdType.swift

import Foundation

public extension Bid {
    var nativoAdType: NativoAdType? {
        bid.ext?.nativo?.nativoAdType
    }

    /// Whether Nativo's renderer expands this creative to fill its container instead of leaving it at the
    /// fixed bid size a standard banner uses.
    var usesNativoRendering: Bool {
        if let nativoAdType {
            // Standard display is the one Nativo type that renders as an ordinary fixed-size banner.
            return nativoAdType != .standardDisplay
        }
        return adm?.range(of: "load.js", options: .caseInsensitive) != nil
    }
}
