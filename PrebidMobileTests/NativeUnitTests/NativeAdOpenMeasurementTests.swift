/*   Copyright 2018-2026 Prebid.org, Inc.

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

/// Covers the Open Measurement native display session `NativeAd` opens against the registered view:
/// when it is created, the order its events reach the OM SDK, and when it is finished. Substitutes a
/// recording wrapper through `OMSessionWrapperRegistry` so none of this touches the real OM SDK.
class NativeAdOpenMeasurementTests: XCTestCase {

    private var previousWrapper: OMSessionWrapper?
    private var wrapper: RecordingWrapper!

    override func setUp() {
        super.setUp()
        previousWrapper = OMSessionWrapperRegistry.wrapper
        wrapper = RecordingWrapper()
        OMSessionWrapperRegistry.register(wrapper)
    }

    override func tearDown() {
        if let previousWrapper {
            OMSessionWrapperRegistry.register(previousWrapper)
        }
        wrapper = nil
        super.tearDown()
    }

    // MARK: - Session creation

    func testSessionIsCreatedFromTheVerificationResourceInTheMarkup() {
        let ad = makeNativeAd(includeOMResource: true)

        ad.registerView(view: UIView(), clickableViews: nil)

        XCTAssertEqual(wrapper.requestedResources.count, 1)
        XCTAssertEqual(wrapper.requestedResources.first?.url, Self.scriptUrl)
        XCTAssertEqual(wrapper.requestedResources.first?.vendorKey, "vendor.com-omid")
        XCTAssertEqual(wrapper.requestedResources.first?.parameters, "params-blob")
        XCTAssertNotNil(ad.omSession)
    }

    func testMarkupWithoutAVerificationResourceOpensNoSession() {
        let ad = makeNativeAd(includeOMResource: false)

        ad.registerView(view: UIView(), clickableViews: nil)

        XCTAssertTrue(wrapper.requestedResources.isEmpty)
        XCTAssertNil(ad.omSession)
    }

    func testSessionIsStartedAndLoadedOnceAtRegistration() {
        let ad = makeNativeAd(includeOMResource: true)

        ad.registerView(view: UIView(), clickableViews: nil)

        let session = wrapper.sessions.first
        XCTAssertEqual(session?.startCount, 1)
        XCTAssertEqual(session?.tracker.events, [.loaded])
    }

    // MARK: - Impression

    /// The session declares `OMIDImpressionTypeOnePixel`, so the OM impression has to ride the same
    /// any-exposure trigger as the ORTB impression pixel rather than a viewable threshold.
    func testImpressionIsSignalledOnceOnTheFirstExposureAndAfterLoaded() {
        let ad = makeNativeAd(includeOMResource: true)
        ad.registerView(view: UIView(), clickableViews: nil)

        for _ in 0..<5 {
            ad.handleExposureChange(exposure(percentage: 1))
        }

        XCTAssertEqual(wrapper.sessions.first?.tracker.events, [.loaded, .impression])
    }

    func testNoImpressionWhileTheAdHasNoExposure() {
        let ad = makeNativeAd(includeOMResource: true)
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 0))

        XCTAssertEqual(wrapper.sessions.first?.tracker.events, [.loaded])
    }

    /// `handleExposureChange` releases the exposure checker once every pixel obligation has fired. The
    /// session has to outlive it, because the verification script keeps measuring off `mainAdView`.
    func testSessionOutlivesTheExposureCheckerBeingReleased() {
        let ad = makeNativeAd(includeOMResource: true)
        ad.registerView(view: UIView(), clickableViews: nil)

        ad.handleExposureChange(exposure(percentage: 1))

        XCTAssertNil(ad.exposureChecker)
        XCTAssertNotNil(ad.omSession)
        XCTAssertEqual(wrapper.sessions.first?.stopCount, 0)
    }

    // MARK: - Teardown

    func testSessionIsFinishedWhenTrackingIsTornDown() {
        let ad = makeNativeAd(includeOMResource: true)
        var view: UIView? = UIView()
        ad.registerView(view: view!, clickableViews: nil)

        // `viewForTracking` is weak, so releasing the view is what lets the expiry path unregister.
        view = nil
        ad.cacheExpired()

        XCTAssertNil(ad.omSession)
        XCTAssertEqual(wrapper.sessions.first?.stopCount, 1)
    }

    // MARK: - Friendly obstructions

    func testObstructionsFoundByTheExposureCheckerAreForwardedToTheSession() {
        let ad = makeNativeAd(includeOMResource: true)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 250))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(container)
        window.makeKeyAndVisible()

        ad.registerView(view: container, clickableViews: nil)

        let expected = ad.exposureChecker?.friendlyObstructionViews() ?? []
        XCTAssertEqual(wrapper.sessions.first?.obstructions.count, expected.count)
        for (registered, found) in zip(wrapper.sessions.first?.obstructions ?? [], expected) {
            XCTAssertIdentical(registered.view, found)
            XCTAssertEqual(registered.purpose, .transparentOverlay)
        }
    }

    // MARK: - Fixtures

    private static let scriptUrl = "https://verification.example.com/omid.js"

    private func makeNativeAd(includeOMResource: Bool) -> NativeAd {
        var trackers: [[String: Any]] = [
            ["event": 1, "method": 1, "url": "https://tracker.test/pixel"]
        ]
        if includeOMResource {
            trackers.append(["event": 1, "method": 2, "url": Self.scriptUrl, "ext": [
                "vendorKey": "vendor.com-omid",
                "verificationParameters": "params-blob"
            ]])
        }

        let admString = String(data: try! JSONSerialization.data(withJSONObject: ["eventtrackers": trackers]),
                               encoding: .utf8)!
        let bidString = String(data: try! JSONSerialization.data(withJSONObject: [
            "id": "bid-1",
            "impid": "imp-1",
            "price": 0.1,
            "adm": admString
        ]), encoding: .utf8)!

        let cacheId = CacheManager.shared.save(content: bidString)!
        return NativeAd.create(cacheId: cacheId)!
    }

    private func exposure(percentage: Float) -> ViewExposure {
        Factory.createViewExposure(exposureFactor: percentage / 100,
                                   visibleRectangle: .zero,
                                   occlusionRectangles: nil as [NSValue]?)
    }
}

// MARK: - Recording doubles

private final class RecordingWrapper: NSObject, OMSessionWrapper {

    struct RequestedResource {
        let url: String
        let vendorKey: String?
        let parameters: String?
    }

    var requestedResources: [RequestedResource] = []
    var sessions: [RecordingSession] = []

    func initializeNativeDisplaySession(_ view: UIView,
                                        omidJSUrl: String,
                                        vendorKey: String?,
                                        parameters: String?) -> OMSession? {
        requestedResources.append(RequestedResource(url: omidJSUrl, vendorKey: vendorKey, parameters: parameters))
        let session = RecordingSession()
        sessions.append(session)
        return session
    }

    func injectJSLib(_ html: String, error: NSErrorPointer) -> String? { html }

    func initializeWebViewSession(_ webView: WKWebView, contentUrl: String?, isJSBasedTracking: Bool) -> OMSession? { nil }

    func initializeNativeVideoSession(_ videoView: UIView, verificationParameters: VideoVerificationParameters?) -> OMSession? { nil }
}

private final class RecordingSession: NSObject, OMSession {

    struct Obstruction {
        let view: UIView
        let purpose: OpenMeasurementFriendlyObstructionPurpose
    }

    let tracker = RecordingEventTracker()
    var startCount = 0
    var stopCount = 0
    var obstructions: [Obstruction] = []

    var eventTracker: EventTrackerProtocol { tracker }

    func start() { startCount += 1 }

    func stop() { stopCount += 1 }

    func addFriendlyObstruction(_ friendlyObstruction: UIView, purpose: OpenMeasurementFriendlyObstructionPurpose) {
        obstructions.append(Obstruction(view: friendlyObstruction, purpose: purpose))
    }
}

private final class RecordingEventTracker: NSObject, EventTrackerProtocol {

    var events: [TrackingEvent] = []

    func trackEvent(_ event: TrackingEvent) { events.append(event) }

    func trackVideoAdLoaded(_ parameters: VideoVerificationParameters) {}

    func trackStartVideo(duration: TimeInterval, volume: Double) {}

    func trackVolumeChanged(playerVolume: Double, deviceVolume: Double) {}
}
