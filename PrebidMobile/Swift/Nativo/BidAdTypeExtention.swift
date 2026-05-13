// NativoBid+AdType.swift

import Foundation

public extension Bid {
    var nativoAdType: NativoAdType? {
        bid.ext?.nativo?.nativoAdType
    }
}
