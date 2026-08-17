/*   Copyright 2018-2025 Prebid.org, Inc.

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

/// Covers which `BannerView` load callback fires for a Life360 win: the Life360-specific one when the
/// delegate conforms to `Life360BannerViewDelegate`, the standard one otherwise.
class Life360BannerViewDelegateTest: XCTestCase {

    private let adSize = CGSize(width: 320, height: 50)

    override func tearDown() {
        Prebid.reset()
        super.tearDown()
    }

    // MARK: - Life360-aware delegate

    func testLife360AwareDelegateReceivesLife360Callback() {
        let delegate = Life360AwareDelegateSpy()
        let bannerView = makeBannerView(
            bidResponse: makeLife360BidResponse(adType: .article),
            delegate: delegate
        )

        simulateAdLoaded(on: bannerView, delegate: delegate)

        XCTAssertEqual(delegate.life360Sizes, [adSize])
        XCTAssertEqual(delegate.standardSizes, [])
    }

    /// Every non-`standardDisplay` ad type is rendered by Life360, so all of them must route to the
    /// Life360 callback.
    func testLife360AwareDelegateReceivesLife360CallbackForEveryLife360RenderedAdType() {
        let life360RenderedAdTypes: [Life360AdType] = [.article, .display, .ctpVideo, .carousel, .stpVideo, .story]

        for adType in life360RenderedAdTypes {
            let delegate = Life360AwareDelegateSpy()
            let bannerView = makeBannerView(
                bidResponse: makeLife360BidResponse(adType: adType),
                delegate: delegate
            )

            simulateAdLoaded(on: bannerView, delegate: delegate)

            XCTAssertEqual(delegate.life360Sizes, [adSize], "ad type \(adType.rawValue)")
            XCTAssertEqual(delegate.standardSizes, [], "ad type \(adType.rawValue)")
        }
    }

    /// `standardDisplay` bids are rendered through the regular display path, so a Life360-aware
    /// delegate must still get the standard callback for them.
    func testLife360AwareDelegateReceivesStandardCallbackForStandardDisplay() {
        let delegate = Life360AwareDelegateSpy()
        let bannerView = makeBannerView(
            bidResponse: makeLife360BidResponse(adType: .standardDisplay),
            delegate: delegate
        )

        simulateAdLoaded(on: bannerView, delegate: delegate)

        XCTAssertEqual(delegate.standardSizes, [adSize])
        XCTAssertEqual(delegate.life360Sizes, [])
    }

    func testLife360AwareDelegateReceivesStandardCallbackWhenAdTypeIsMissing() {
        let delegate = Life360AwareDelegateSpy()
        let bannerView = makeBannerView(
            bidResponse: makeLife360BidResponse(adType: nil),
            delegate: delegate
        )

        simulateAdLoaded(on: bannerView, delegate: delegate)

        XCTAssertEqual(delegate.standardSizes, [adSize])
        XCTAssertEqual(delegate.life360Sizes, [])
    }

    func testLife360AwareDelegateReceivesStandardCallbackForNonLife360BidResponse() {
        let delegate = Life360AwareDelegateSpy()
        let bannerView = makeBannerView(
            bidResponse: makePrebidBidResponse(),
            delegate: delegate
        )

        simulateAdLoaded(on: bannerView, delegate: delegate)

        XCTAssertEqual(delegate.standardSizes, [adSize])
        XCTAssertEqual(delegate.life360Sizes, [])
    }

    // MARK: - Delegate that hasn't opted in

    /// A host still on plain `BannerViewDelegate` must keep working: a Life360 win falls back to the
    /// standard callback rather than being dropped.
    func testStandardDelegateFallsBackToStandardCallbackOnLife360Win() {
        let delegate = StandardDelegateSpy()
        let bannerView = makeBannerView(
            bidResponse: makeLife360BidResponse(adType: .article),
            delegate: delegate
        )

        simulateAdLoaded(on: bannerView, delegate: delegate)

        XCTAssertEqual(delegate.standardSizes, [adSize])
    }

    /// Dispatch is by protocol conformance, not selector lookup — a delegate that implements the
    /// Life360 selector without conforming to `Life360BannerViewDelegate` gets the standard callback.
    func testDelegateImplementingLife360SelectorWithoutConformingGetsStandardCallback() {
        let delegate = Life360SelectorWithoutConformanceDelegateSpy()
        let bannerView = makeBannerView(
            bidResponse: makeLife360BidResponse(adType: .article),
            delegate: delegate
        )

        simulateAdLoaded(on: bannerView, delegate: delegate)

        XCTAssertEqual(delegate.standardSizes, [adSize])
        XCTAssertEqual(delegate.life360Sizes, [])
    }

    func testLife360WinWithoutDelegateDoesNotCrash() {
        let bannerView = makeBannerView(
            bidResponse: makeLife360BidResponse(adType: .article),
            delegate: nil
        )

        simulateAdLoaded(on: bannerView)
        flushMainQueue()

        XCTAssertNotNil(bannerView.deployedView)
    }

    // MARK: - Helpers

    private func makeBannerView(
        bidResponse: BidResponse?,
        delegate: BannerViewDelegate?
    ) -> BannerView {
        let bannerView = BannerView(
            frame: CGRect(origin: .zero, size: adSize),
            configID: "test-config-id",
            adSize: adSize
        )
        bannerView.delegate = delegate
        bannerView.adLoadFlowController?.bidResponse = bidResponse
        return bannerView
    }

    /// A Life360 bid response carrying a single winning bid whose ext advertises `adType`.
    private func makeLife360BidResponse(adType: Life360AdType?) -> Life360BidResponse {
        Life360BidResponse(rawBidResponse: makeRawBidResponse(life360AdType: adType))
    }

    /// A regular Prebid bid response — same shape, but not a `Life360BidResponse`.
    private func makePrebidBidResponse() -> BidResponse {
        BidResponse(rawBidResponse: makeRawBidResponse(life360AdType: nil))
    }

    private func makeRawBidResponse(life360AdType: Life360AdType?) -> RawBidResponse {
        let rawBid = ORTBBid<ORTBBidExt>(bidID: "test-bid-id", impid: "test-imp-id", price: 1.0)
        rawBid.w = NSNumber(value: Int(adSize.width))
        rawBid.h = NSNumber(value: Int(adSize.height))

        let ext = ORTBBidExt()
        var life360JSON: [String: Any] = [:]
        if let life360AdType {
            life360JSON["life360AdType"] = NSNumber(value: life360AdType.rawValue)
        }
        ext.life360 = ORTBBidExtLife360(jsonDictionary: life360JSON)
        rawBid.ext = ext

        let rawBidResponse = RawBidResponse(requestID: "test-request-id")
        rawBidResponse.seatbid = [.init(bid: [rawBid])]
        return rawBidResponse
    }

    /// Drives the same entry point the ad loader uses once a creative has been rendered, then waits
    /// for the load callback the delegate spy is expecting.
    private func simulateAdLoaded(on bannerView: BannerView, delegate: LoadCallbackRecording) {
        let exp = expectation(description: "load callback called")
        delegate.loadCallbackExpectation = exp

        simulateAdLoaded(on: bannerView)

        wait(for: [exp], timeout: 1.0)
    }

    private func simulateAdLoaded(on bannerView: BannerView) {
        let adLoader = BannerAdLoader(delegate: bannerView)
        bannerView.bannerAdLoader(adLoader, loadedAdView: renderedView(for: bannerView), adSize: adSize)
    }

    /// The view a Life360 win actually deploys.
    ///
    /// Life360 demand is rendered by `Life360RendererInternal`, which returns a `DisplayView` carrying the
    /// winning bid, and that bid is what identifies the demand — the flow controller's `bidResponse` is
    /// reassigned part-way through a load, so it can describe a later cycle or another ad unit. A plain
    /// `UIView` means the ad server won, and the ad server never renders Life360 demand.
    private func renderedView(for bannerView: BannerView) -> UIView {
        guard let bid = bannerView.lastBidResponse?.winningBid else {
            return UIView()
        }
        return DisplayView(frame: CGRect(origin: .zero, size: adSize),
                           bid: bid,
                           adConfiguration: bannerView.adUnitConfig)
    }

    // Processes all pending main-queue work queued before this call.
    private func flushMainQueue() {
        let exp = expectation(description: "main queue flush")
        DispatchQueue.main.async { exp.fulfill() }
        waitForExpectations(timeout: 1.0)
    }
}

/// Lets the test wait on whichever load callback the SDK chooses to send.
private protocol LoadCallbackRecording: AnyObject {
    var loadCallbackExpectation: XCTestExpectation? { get set }
}

private class Life360AwareDelegateSpy: NSObject, Life360BannerViewDelegate, LoadCallbackRecording {
    var life360Sizes: [CGSize] = []
    var standardSizes: [CGSize] = []
    var loadCallbackExpectation: XCTestExpectation?

    func bannerViewPresentationController() -> UIViewController? { nil }

    func bannerView(_ bannerView: BannerView, didReceiveLife360AdWithSize adSize: CGSize) {
        life360Sizes.append(adSize)
        loadCallbackExpectation?.fulfill()
    }

    func bannerView(_ bannerView: BannerView, didReceiveAdWithAdSize adSize: CGSize) {
        standardSizes.append(adSize)
        loadCallbackExpectation?.fulfill()
    }
}

private class StandardDelegateSpy: NSObject, BannerViewDelegate, LoadCallbackRecording {
    var standardSizes: [CGSize] = []
    var loadCallbackExpectation: XCTestExpectation?

    func bannerViewPresentationController() -> UIViewController? { nil }

    func bannerView(_ bannerView: BannerView, didReceiveAdWithAdSize adSize: CGSize) {
        standardSizes.append(adSize)
        loadCallbackExpectation?.fulfill()
    }
}

/// Implements the Life360 selector without declaring conformance, mimicking a host that was written
/// against the old optional `BannerViewDelegate` method.
private class Life360SelectorWithoutConformanceDelegateSpy: NSObject, BannerViewDelegate, LoadCallbackRecording {
    var life360Sizes: [CGSize] = []
    var standardSizes: [CGSize] = []
    var loadCallbackExpectation: XCTestExpectation?

    func bannerViewPresentationController() -> UIViewController? { nil }

    @objc func bannerView(_ bannerView: BannerView, didReceiveLife360AdWithSize adSize: CGSize) {
        life360Sizes.append(adSize)
        loadCallbackExpectation?.fulfill()
    }

    func bannerView(_ bannerView: BannerView, didReceiveAdWithAdSize adSize: CGSize) {
        standardSizes.append(adSize)
        loadCallbackExpectation?.fulfill()
    }
}
