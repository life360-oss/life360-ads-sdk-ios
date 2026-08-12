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

#if canImport(AppHarbrSDK)

import XCTest
import WebKit
import AppHarbrSDK

@testable @_spi(PBMInternal) import Life360AdsSDK

/// Covers what `Life360AppHarbrQualityProvider` reports to AppHarbr.
///
/// Compiled and run against the real AppHarbrSDK, which this target links weakly — so this file only
/// exists where the framework is on the search path, the same condition that compiles the provider.
/// Registration is the app's job — it hands `shared` to
/// `AppHarbrPrebidLife360Adapter.initAdQualityService(_:)` — so what is covered here is what the
/// provider reports back once AppHarbr asks.
class Life360AppHarbrQualityProviderTest: XCTestCase {

    private let adSize = CGSize(width: 320, height: 50)

    func testWinningBid_reportsTheWinningBidOfTheBanner() throws {
        let bannerView = makeBannerView(
            bidResponse: NativoBidFabricator.makePrebidBidResponse(
                price: 1.5,
                width: 320,
                height: 50,
                crid: "creative-7"
            )
        )

        let properties = try XCTUnwrap(
            Life360AppHarbrQualityProvider.shared.winningBid(
                for: "unit",
                adFormat: .banner,
                mediationObject: bannerView
            )
        )

        XCTAssertEqual(properties.mediationAdUnitId, "unit")
        XCTAssertEqual(properties.adNetworkUnitId, "unit")
        XCTAssertEqual(properties.creativeId, "creative-7")
        XCTAssertEqual(properties.adFormat, .banner)
        XCTAssertEqual(properties.adNetwork, .prebidLife360)
        XCTAssertEqual(properties.contentType, .html)
        XCTAssertEqual(properties.customTargeting?["hb_bidder"] as? String, "test-bidder")

        // The content is the bid response narrowed to the single winning bid.
        let content = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(properties.content.utf8)) as? [String: Any]
        )
        let seatbid = try XCTUnwrap(content["seatbid"] as? [[String: Any]])
        let bids = try XCTUnwrap(seatbid.first?["bid"] as? [[String: Any]])
        XCTAssertEqual(bids.count, 1)
        XCTAssertEqual(bids.first?["crid"] as? String, "creative-7")
    }

    /// The ad format is AppHarbr's own value echoed back, so a format this SDK does not know about
    /// still round-trips correctly.
    func testWinningBid_reportsTheAdFormatAppHarbrAskedAbout() throws {
        let bannerView = makeBannerView(
            bidResponse: NativoBidFabricator.makePrebidBidResponse(
                price: 1.5,
                width: 320,
                height: 50,
                crid: "creative-7"
            )
        )

        let properties = try XCTUnwrap(
            Life360AppHarbrQualityProvider.shared.winningBid(
                for: "unit",
                adFormat: .native,
                mediationObject: bannerView
            )
        )

        XCTAssertEqual(properties.adFormat, .native)
    }

    func testWinningBid_withoutABannerView_returnsNil() {
        XCTAssertNil(
            Life360AppHarbrQualityProvider.shared.winningBid(
                for: "unit",
                adFormat: .banner,
                mediationObject: NSObject()
            )
        )
    }

    func testWinningBid_beforeABidIsResolved_returnsNil() {
        XCTAssertNil(
            Life360AppHarbrQualityProvider.shared.winningBid(
                for: "unit",
                adFormat: .banner,
                mediationObject: makeBannerView(bidResponse: nil)
            )
        )
    }

    /// No creative has been set up on a freshly built banner, so there is no web view to report yet —
    /// the bid still is.
    func testWinningBid_beforeACreativeIsSetUp_reportsTheBidWithoutAWebView() throws {
        let bannerView = makeBannerView(
            bidResponse: NativoBidFabricator.makePrebidBidResponse(
                price: 1.5,
                width: 320,
                height: 50,
                crid: "creative-7"
            )
        )

        let properties = try XCTUnwrap(
            Life360AppHarbrQualityProvider.shared.winningBid(
                for: "unit",
                adFormat: .banner,
                mediationObject: bannerView
            )
        )

        XCTAssertEqual(properties.creativeId, "creative-7")
        XCTAssertNil(properties.webView)
    }

    func testAdNetworkVersion_reportsTheSDKVersion() {
        XCTAssertEqual(Life360AppHarbrQualityProvider.shared.adNetworkVersion, Life360Ads.shared.version)
    }

    // MARK: - Helpers

    private func makeBannerView(bidResponse: BidResponse?) -> BannerView {
        let bannerView = BannerView(
            frame: CGRect(origin: .zero, size: adSize),
            configID: "test-config-id",
            adSize: adSize
        )
        bannerView.adLoadFlowController?.bidResponse = bidResponse
        return bannerView
    }
}

#endif
