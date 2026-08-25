//
//  AdSlotView.swift
//  Life360AdsDemoiOS
//

import UIKit

/// Base for the three ad slots, holding only what the feed needs to treat them interchangeably: somewhere
/// to install the ad, a hook to request it, and a tagged console log.
///
/// No chrome of its own — the slot is the ad. Anything drawn around a creative is one more thing to rule
/// out when a viewability or tracking event doesn't fire when expected.
class AdSlotView: UIView {

    /// Prefix on printed lines so a console filtered by ad type shows one slot.
    private let logTag: String

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init(logTag: String) {
        self.logTag = logTag
        super.init(frame: .zero)
        // Clipped so the slot's bounds are an honest picture of the space the publisher gave the ad.
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Requests the ad. Subclasses override; the base implementation only records the attempt.
    func loadAd() {
        report("requesting ad")
    }

    /// Prints a timestamped SDK event. Timestamps matter here because the point is *when* a callback fires
    /// relative to the ad crossing the edge of the screen, not just that it fired.
    func report(_ event: String) {
        print("[\(logTag)] \(Self.timestampFormatter.string(from: Date()))  \(event)")
    }
}
