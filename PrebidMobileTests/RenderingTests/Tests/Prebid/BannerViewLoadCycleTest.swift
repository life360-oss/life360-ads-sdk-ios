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

/// One `BannerView` loading more than once. Each cycle must report the ad and size it actually
/// produced, and a cycle that produces nothing must fail rather than go quiet.
///
/// Shares the render substitution described on `BannerViewConcurrencyTest`: `xctest` has no host
/// application, so the creative load is driven explicitly rather than through `WKWebView`.
class BannerViewLoadCycleTest: XCTestCase {

    private let flowTimeout: TimeInterval = 10
    private let prebidSize = CGSize(width: 320, height: 50)
    private let adServerSize = CGSize(width: 728, height: 90)

    private var recordingDelegate: RecordingBannerViewDelegate!
    private var collector: DisplayViewCollector!
    private var eventHandler: ScriptedBannerEventHandler!
    private var bannerView: BannerView!
    private var adLoader: BannerAdLoader!

    override func setUp() {
        super.setUp()
        recordingDelegate = RecordingBannerViewDelegate()
        collector = DisplayViewCollector()

        PrebidMobilePluginRegister.shared.unregisterAllPlugins()
        Prebid.registerPluginRenderer(CapturingPrebidRenderer(collector: collector))
        Prebid.registerPluginRenderer(CapturingNativoRenderer(collector: collector))
    }

    override func tearDown() {
        adLoader = nil
        bannerView = nil
        eventHandler = nil
        collector = nil
        recordingDelegate = nil
        PrebidMobilePluginRegister.shared.unregisterAllPlugins()
        Prebid.reset()
        super.tearDown()
    }

    /// The ad server wins the first cycle and the SDK wins the second. The second cycle must deploy its
    /// own view at its own size — the ad-server view from the first cycle is finished with.
    func testAdServerWinThenSdkWin_secondCycleDeploysItsOwnAd() {
        let adServerView = UIView(frame: CGRect(origin: .zero, size: adServerSize))
        makeBannerView(script: [.adServerWins(view: adServerView, size: adServerSize), .sdkWins])

        // Cycle 1: the ad server's view is deployed at the ad server's size.
        let firstReport = expectSuccess(description: "cycle 1 reports success")
        bannerView.loadAd()
        wait(for: [firstReport], timeout: flowTimeout)

        XCTAssertIdentical(bannerView.deployedView, adServerView)
        XCTAssertEqual(recordingDelegate.reportedSize(for: bannerView), adServerSize)

        // Cycle 2: the SDK renders its own DisplayView.
        let secondReport = expectSuccess(description: "cycle 2 reports success")
        bannerView.loadAd()
        let displayView = awaitDisplayView()
        finishCreativeLoad(displayView)
        wait(for: [secondReport], timeout: flowTimeout)

        XCTAssertIdentical(
            bannerView.deployedView,
            displayView,
            "the second cycle deployed the first cycle's ad-server view"
        )
        XCTAssertEqual(
            recordingDelegate.reportedSizes(for: bannerView).last,
            prebidSize,
            "the second cycle reported the first cycle's size"
        )
        XCTAssertEqual(recordingDelegate.failureCount(for: bannerView), 0)
    }

    /// Reaching the deploy step with nothing to deploy must surface as a failure. Left silent, the ad
    /// unit would sit idle having promised the publisher neither an ad nor an error.
    func testReadyToDeployWithNoAdObject_reportsFailure() throws {
        makeBannerView(script: [.sdkWins])
        let controller = try XCTUnwrap(bannerView.adLoadFlowController)

        let failed = expectation(description: "an empty deploy is reported as a failure")
        recordingDelegate.onFailure = { _, _ in failed.fulfill() }

        // Advance straight to the deploy step without any cycle having produced an ad object.
        controller.adLoaderLoadedPrebidAd(adLoader)

        wait(for: [failed], timeout: flowTimeout)
        XCTAssertEqual(controller.flowState, .loadingFailed)
        XCTAssertEqual(recordingDelegate.successCount(for: bannerView), 0)
    }

    // MARK: - Helpers

    private func makeBannerView(script: [ScriptedBannerEventHandler.Step]) {
        eventHandler = ScriptedBannerEventHandler(script: script, adSizes: [prebidSize])

        bannerView = BannerView(
            frame: CGRect(origin: .zero, size: prebidSize),
            configID: "config-cycle",
            adSize: prebidSize,
            eventHandler: eventHandler
        )
        // Only a negative value disables auto-refresh; 0 is clamped up to refreshIntervalMin.
        bannerView.refreshInterval = -1
        bannerView.delegate = recordingDelegate

        adLoader = BannerAdLoader(delegate: bannerView)
        bannerView.adLoadFlowController = AdLoadFlowController(
            bidRequesterFactory: { _ in
                StubBidRequester(response: nil, error: PBMError.noWinningBid())
            },
            adLoader: adLoader,
            adUnitConfig: bannerView.adUnitConfig,
            delegate: bannerView,
            configValidationBlock: { _, _ in true },
            nativoBidRequesterFactory: { [prebidSize] _ in
                StubBidRequester(
                    response: NativoBidFabricator.makeNativoBidResponse(
                        price: 1.0,
                        width: Int(prebidSize.width),
                        height: Int(prebidSize.height),
                        crid: "crid-cycle"
                    )
                )
            }
        )
    }

    private func expectSuccess(description: String) -> XCTestExpectation {
        let exp = expectation(description: description)
        exp.assertForOverFulfill = false
        recordingDelegate.onSuccess = { _, _ in exp.fulfill() }
        return exp
    }

    private func awaitDisplayView() -> DisplayView {
        let created = expectation(description: "a DisplayView is created")
        created.assertForOverFulfill = false
        collector.onCreate = { created.fulfill() }
        if !collector.views.isEmpty { created.fulfill() }
        wait(for: [created], timeout: flowTimeout)
        collector.onCreate = nil
        return collector.views[collector.views.count - 1]
    }

    private func finishCreativeLoad(_ view: DisplayView) {
        view.loadingDelegate?.displayViewDidLoadAd(view)
    }
}

// MARK: - Test doubles

/// A `BannerEventHandler` that answers each `requestAd` call differently, so one `BannerView` can be
/// driven through an ad-server win and an SDK win in sequence.
final class ScriptedBannerEventHandler: NSObject, BannerEventHandler {

    enum Step {
        case adServerWins(view: UIView, size: CGSize)
        case sdkWins
        case fails(Error)
    }

    weak var loadingDelegate: BannerEventLoadingDelegate?
    weak var interactionDelegate: BannerEventInteractionDelegate?

    var adSizes: [CGSize]

    private var script: [Step]
    private var nextStep = 0

    init(script: [Step], adSizes: [CGSize]) {
        self.script = script
        self.adSizes = adSizes
        super.init()
    }

    func requestAd(with bidResponse: BidResponse?) {
        guard nextStep < script.count else {
            XCTFail("ScriptedBannerEventHandler ran out of steps at call \(nextStep + 1)")
            return
        }
        let step = script[nextStep]
        nextStep += 1

        switch step {
        case .adServerWins(let view, let size):
            loadingDelegate?.adServerDidWin(view, adSize: size)
        case .sdkWins:
            loadingDelegate?.sdkDidWin(bidResponse)
        case .fails(let error):
            loadingDelegate?.failedWithError(error)
        }
    }

    func trackImpression() {}
    func trackClick() {}
}
