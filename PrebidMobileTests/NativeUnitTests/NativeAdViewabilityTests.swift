/*   Copyright 2018-2019 Prebid.org, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import XCTest
@testable @_spi(PBMInternal) import Life360AdsSDK

/// Covers the ORTB Native 1.2 §7.6 event-type gating in `NativeAd` — which `eventtrackers` entry
/// fires under which condition. Exercises `handleExposureChange` directly with fabricated
/// `ViewExposure` values (via `Factory.createViewExposure`), so none of this needs a real window,
/// a live view hierarchy, or waiting on real timer durations.
class NativeAdViewabilityTests: XCTestCase {

    // MARK: - Fixtures

    private func makeNativeAd(eventTrackers: [[String: Any]]? = nil) -> NativeAd {
        var admDict: [String: Any] = [:]
        if let eventTrackers {
            admDict["eventtrackers"] = eventTrackers
        }
        let admData = try! JSONSerialization.data(withJSONObject: admDict)
        let admString = String(data: admData, encoding: .utf8)!

        let bidDict: [String: Any] = [
            "id": "bid-1",
            "impid": "imp-1",
            "price": 0.1,
            "adm": admString
        ]
        let bidData = try! JSONSerialization.data(withJSONObject: bidDict)
        let bidString = String(data: bidData, encoding: .utf8)!

        let cacheId = CacheManager.shared.save(content: bidString)!
        return NativeAd.create(cacheId: cacheId)!
    }

    private func tracker(event: Int) -> [String: Any] {
        ["event": event, "method": 1, "url": "https://testUrl.com/events/tracker/\(event)"]
    }

    private func exposure(percentage: Float) -> ViewExposure {
        Factory.createViewExposure(exposureFactor: percentage / 100, visibleRectangle: .zero, occlusionRectangles: nil as [NSValue]?)
    }

    // MARK: - isMatch routing

    func testIsMatchRoutesEachStandardEventTypeToItself() {
        let ad = makeNativeAd()

        XCTAssertTrue(ad.isEventTypeMatch(makeTracker(event: 1), .Impression))
        XCTAssertTrue(ad.isEventTypeMatch(makeTracker(event: 2), .ViewableImpression50))
        XCTAssertTrue(ad.isEventTypeMatch(makeTracker(event: 3), .ViewableImpression100))
        XCTAssertTrue(ad.isEventTypeMatch(makeTracker(event: 4), .ViewableVideoImpression50))
    }

    func testIsMatchDoesNotCrossStandardEventTypes() {
        let ad = makeNativeAd()
        let mrc50Tracker = makeTracker(event: 2)

        XCTAssertFalse(ad.isEventTypeMatch(mrc50Tracker, .Impression))
        XCTAssertFalse(ad.isEventTypeMatch(mrc50Tracker, .ViewableImpression100))
        XCTAssertFalse(ad.isEventTypeMatch(mrc50Tracker, .ViewableVideoImpression50))
    }

    func testIsMatchFoldsExchangeSpecificAndMissingEventIntoImpression() {
        let ad = makeNativeAd()

        XCTAssertTrue(ad.isEventTypeMatch(makeTracker(event: 555), .Impression))
        XCTAssertFalse(ad.isEventTypeMatch(makeTracker(event: 555), .ViewableImpression50))

        XCTAssertTrue(ad.isEventTypeMatch(makeTracker(event: nil), .Impression))
    }

    private func makeTracker(event: Int?) -> NativeEventTrackerResponse {
        let tracker = NativeEventTrackerResponse()
        tracker.event = event
        return tracker
    }

    // MARK: - Timer setup only for event types actually present

    func testSetupOnlyCreatesTimersForEventTypesPresentInResponse() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 1), tracker(event: 2)])

        ad.registerView(view: UIView(), clickableViews: nil)

        XCTAssertEqual(ad.viewabilityTimers.count, 1)
        XCTAssertNotNil(ad.viewabilityTimers[EventType.ViewableImpression50.value])
        XCTAssertNil(ad.viewabilityTimers[EventType.ViewableImpression100.value])
        XCTAssertNil(ad.viewabilityTimers[EventType.ViewableVideoImpression50.value])
    }

    func testSetupCreatesNoTimersWhenResponseHasNoEventTrackers() {
        let ad = makeNativeAd(eventTrackers: nil)

        ad.registerView(view: UIView(), clickableViews: nil)

        XCTAssertTrue(ad.viewabilityTimers.isEmpty)
        // Regression guard: exposure monitoring (and therefore the internal impression/billing
        // pixel) must still be set up even when the response has no ORTB `eventtrackers` at all.
        XCTAssertNotNil(ad.exposureChecker)
    }

    // MARK: - Threshold gating

    func testMrc50TimerOnlyResumesAtOrAbove50PercentExposure() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 2)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 49))
        XCTAssertFalse(ad.viewabilityTimers[EventType.ViewableImpression50.value]!.isRunning)

        ad.handleExposureChange(exposure(percentage: 50))
        XCTAssertTrue(ad.viewabilityTimers[EventType.ViewableImpression50.value]!.isRunning)
    }

    func testMrc100TimerOnlyResumesAtFullExposure() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 3)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 99))
        XCTAssertFalse(ad.viewabilityTimers[EventType.ViewableImpression100.value]!.isRunning)

        ad.handleExposureChange(exposure(percentage: 100))
        XCTAssertTrue(ad.viewabilityTimers[EventType.ViewableImpression100.value]!.isRunning)
    }

    func testVideo50TimerUsesSameThresholdAsMrc50() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 4)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 49))
        XCTAssertFalse(ad.viewabilityTimers[EventType.ViewableVideoImpression50.value]!.isRunning)

        ad.handleExposureChange(exposure(percentage: 50))
        XCTAssertTrue(ad.viewabilityTimers[EventType.ViewableVideoImpression50.value]!.isRunning)
    }

    func testTimersIndependentlyTrackDifferentThresholds() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 2), tracker(event: 3), tracker(event: 4)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 60))

        XCTAssertTrue(ad.viewabilityTimers[EventType.ViewableImpression50.value]!.isRunning)
        XCTAssertTrue(ad.viewabilityTimers[EventType.ViewableVideoImpression50.value]!.isRunning)
        XCTAssertFalse(ad.viewabilityTimers[EventType.ViewableImpression100.value]!.isRunning)
    }

    func testTimerPausesAgainWhenExposureDropsBelowThreshold() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 2)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 60))
        XCTAssertTrue(ad.viewabilityTimers[EventType.ViewableImpression50.value]!.isRunning)

        ad.handleExposureChange(exposure(percentage: 0))
        XCTAssertFalse(ad.viewabilityTimers[EventType.ViewableImpression50.value]!.isRunning)
    }

    // MARK: - Impression has no dwell duration

    func testImpressionFiresImmediatelyOnAnyNonzeroExposure() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 1)])
        ad.registerView(view: UIView(), clickableViews: nil)

        XCTAssertFalse(ad.impressionHasBeenTracked)

        ad.handleExposureChange(exposure(percentage: 1))

        XCTAssertTrue(ad.impressionHasBeenTracked)
    }

    func testImpressionDoesNotFireAtZeroExposure() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 1)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 0))

        XCTAssertFalse(ad.impressionHasBeenTracked)
    }

    // MARK: - Exposure teardown

    func testExposureCheckerTornDownOnceEverythingTrackedHasFired() {
        // Only an impression tracker — no duration-gated type is present, so once impression
        // fires (synchronously, no timer involved) there's nothing left to watch for.
        let ad = makeNativeAd(eventTrackers: [tracker(event: 1)])
        ad.registerView(view: UIView(), clickableViews: nil)
        XCTAssertNotNil(ad.exposureChecker)

        ad.handleExposureChange(exposure(percentage: 1))

        XCTAssertNil(ad.exposureChecker)
    }

    func testExposureCheckerStaysAliveWhileADurationGatedTimerHasNotFired() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 1), tracker(event: 2)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 60))

        // Impression fired immediately, but the mrc50 timer has only just started counting down —
        // it hasn't reached its 1-second duration yet, so exposure monitoring must stay active.
        XCTAssertTrue(ad.impressionHasBeenTracked)
        XCTAssertFalse(ad.viewabilityTimers[EventType.ViewableImpression50.value]!.hasFired)
        XCTAssertNotNil(ad.exposureChecker)
    }

    // MARK: - Fires only once

    /// A test-only delegate that just counts how many times `adDidLogImpression` is invoked.
    private final class RecordingDelegate: NSObject, NativeAdEventDelegate {
        var impressionLogCount = 0
        func adDidLogImpression(ad: NativeAd) {
            impressionLogCount += 1
        }
    }

    /// The only externally-observable signal for "the impression tracker actually reached the
    /// network and succeeded" is the `adDidLogImpression` delegate callback, so this test hits a
    /// real, known-good endpoint (the same one `TrackerManagerTests` already relies on) rather than
    /// a fake URL that would never call back at all.
    func testImpressionTrackerFiresExactlyOnceEvenWhenExposureChangesRepeatedly() {
        let ad = makeNativeAd(eventTrackers: [
            ["event": 1, "method": 1, "url": "https://acdn.adnxs.com/mobile/native_test/empty_response.json"]
        ])
        let delegate = RecordingDelegate()
        ad.delegate = delegate
        ad.registerView(view: UIView(), clickableViews: nil)

        // Simulate the ad being scrolled through several qualifying exposure changes — the guard
        // on `impressionHasBeenTracked` means only the first of these should ever reach the network.
        for _ in 0..<5 {
            ad.handleExposureChange(exposure(percentage: 60))
        }

        let networkFireHadTimeToComplete = expectation(description: #function)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            networkFireHadTimeToComplete.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertEqual(delegate.impressionLogCount, 1)
    }

    /// For the duration-gated types, the single-fire guarantee comes from
    /// `PausableCountdownTimer.resume()` being a no-op once `hasFired` is true. This exercises that
    /// guarantee for real (waiting out the actual 1-second duration) rather than just re-asserting
    /// that the guard exists in source.
    func testDurationGatedTimerFiresOnlyOnceEvenIfExposureToggledAfterFiring() {
        let ad = makeNativeAd(eventTrackers: [tracker(event: 2)])
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 60))

        let timerFired = expectation(description: #function)
        let pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if ad.viewabilityTimers[EventType.ViewableImpression50.value]!.hasFired {
                timer.invalidate()
                timerFired.fulfill()
            }
        }
        waitForExpectations(timeout: 2)
        pollTimer.invalidate()

        // The ad keeps getting scrolled back through the same qualifying exposure range after
        // already firing — none of these should ever resume (and therefore re-fire) the timer.
        for _ in 0..<3 {
            ad.handleExposureChange(exposure(percentage: 0))
            ad.handleExposureChange(exposure(percentage: 60))
            XCTAssertFalse(ad.viewabilityTimers[EventType.ViewableImpression50.value]!.isRunning)
        }
    }

    /// There's no delegate callback for mrc50 (that's impression-only), so this counts real
    /// outgoing requests via a `URLProtocol` stub instead — a test-side interception that needs no
    /// production code changes, since `TrackerManager` fires through `URLSession.shared`.
    func testAllThreeMrc50TrackersFireExactlyOnceEach() {
        FiredURLCountingProtocol.reset()
        URLProtocol.registerClass(FiredURLCountingProtocol.self)
        defer { URLProtocol.unregisterClass(FiredURLCountingProtocol.self) }

        let urls = ["https://tracker.test/1", "https://tracker.test/2", "https://tracker.test/3"]
        let ad = makeNativeAd(eventTrackers: urls.map { ["event": 2, "method": 1, "url": $0] })
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 60))

        // Wait for the real 1-second mrc50 duration to elapse and actually fire.
        let timerFired = expectation(description: "\(#function)-fired")
        let pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if ad.viewabilityTimers[EventType.ViewableImpression50.value]!.hasFired {
                timer.invalidate()
                timerFired.fulfill()
            }
        }
        waitForExpectations(timeout: 2)
        pollTimer.invalidate()

        waitForNetworkRequestsToSettle()

        for url in urls {
            XCTAssertEqual(FiredURLCountingProtocol.firedURLCounts[url], 1, "\(url) should have fired exactly once")
        }
        XCTAssertEqual(FiredURLCountingProtocol.firedURLCounts.count, 3)

        // Re-exposing repeatedly afterward shouldn't cause any of the three to fire again.
        for _ in 0..<3 {
            ad.handleExposureChange(exposure(percentage: 0))
            ad.handleExposureChange(exposure(percentage: 60))
        }
        waitForNetworkRequestsToSettle()

        for url in urls {
            XCTAssertEqual(FiredURLCountingProtocol.firedURLCounts[url], 1, "\(url) should still have fired exactly once")
        }
    }

    private func waitForNetworkRequestsToSettle() {
        let settled = expectation(description: "network requests settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            settled.fulfill()
        }
        waitForExpectations(timeout: 2)
    }
}

/// Intercepts requests to the reserved `.test` TLD and counts how many times each exact URL was
/// requested, instead of hitting any real network.
private final class FiredURLCountingProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]

    static var firedURLCounts: [String: Int] {
        lock.withLock { counts }
    }

    static func reset() {
        lock.withLock { counts = [:] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "tracker.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let urlString = request.url?.absoluteString {
            Self.lock.withLock { Self.counts[urlString, default: 0] += 1 }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
