//
//  Life360AppHarbrQualityProvider.swift
//

#if canImport(AppHarbrSDK)

import Foundation
import WebKit
import AppHarbrSDK

/// Reports Life360/Prebid banner bids to AppHarbr so it can scan them for ad quality.
///
/// Compiled only where AppHarbrSDK is on the module search path — in practice, an app that declares
/// AppHarbr as a dependency — so the types below are the framework's own and the compiler checks every
/// one of them against the version the app actually ships.
///
/// The app registers `shared` once, after initializing AppHarbr:
///
/// ```swift
/// AppHarbrPrebidLife360Adapter.initAdQualityService(Life360AppHarbrQualityProvider.shared)
/// ```
///
/// and hands each banner to AppHarbr itself, via
/// `AH.addBanner(with: .prebidLife360, adObject: bannerView, delegate:)`.
public final class Life360AppHarbrQualityProvider: NSObject, AdQualityAdNetworkProtocol {

    /// The provider to register with AppHarbr — one instance for the process, since AppHarbr does not
    /// document whether it keeps a strong reference to the provider it is given.
    public static let shared = Life360AppHarbrQualityProvider()

    private override init() {
        super.init()
    }
    
    public func initAdQualityService() -> Bool {
        AppHarbrPrebidLife360Adapter.initAdQualityService(self)
    }

    // MARK: - AdQualityAdNetworkProtocol

    public var adNetworkVersion: String {
        Life360Ads.shared.version
    }

    public func adNetworkAdapterName(for adFormat: AppHarbrSDK.AdFormat) -> String {
        "Life360AdsSDK-appHarbrAdapter"
    }

    public func winningBid(
        for mediationAdUnitId: String,
        adFormat: AppHarbrSDK.AdFormat,
        mediationObject: Any
    ) -> AdQualityAdNetworkProperties? {

        guard let bannerView = mediationObject as? BannerView else {
            Log.error("Life360AppHarbrQualityProvider: mediationObject is not a BannerView")
            return nil
        }

        guard let jsonString = bannerView.currentWinningBidJSON() else {
            Log.debug("Life360AppHarbrQualityProvider: no winning bid resolved yet")
            return nil
        }

        let webView = bannerView.getAppHarbrWebView()
        if webView == nil {
            Log.debug("Life360AppHarbrQualityProvider: no current-creative webview found yet")
        }

        return AdQualityAdNetworkProperties(
            mediationAdUnitId: mediationAdUnitId,
            adFormat: adFormat,
            adNetwork: .prebidLife360,
            adNetworkUnitId: mediationAdUnitId,
            contentType: .html,
            content: jsonString,
            creativeId: bannerView.currentWinningBidCreativeId() ?? "",
            webView: webView,
            customTargeting: bannerView.currentWinningBidCustomTargeting()
        )
    }

    public func willBlockAd(
        cleanCacheFor mediationAdUnitId: String,
        adFormat: AppHarbrSDK.AdFormat,
        mediationObject: Any,
        adNetworkUnitId: String,
        creativeId: String
    ) {
        Log.info(
            "Life360AppHarbrQualityProvider: AppHarbr will block unit \(mediationAdUnitId), "
                + "creative \(creativeId)"
        )
    }
}

internal extension BannerView {

    @objc func getAppHarbrWebView() -> WKWebView? {
        guard let displayView = deployedView as? DisplayView else {
            Log.debug("no deployed DisplayView yet")
            return nil
        }
        guard let creative = displayView.adViewManager?.currentCreative else {
            Log.debug("no current creative set up yet")
            return nil
        }
        guard let creativeView = creative.view else {
            Log.debug("current creative has no view yet")
            return nil
        }
        guard let webView = creativeView as? WebView_Protocol else {
            Log.debug("current creative's view is not a WebView_Protocol")
            return nil
        }
        return webView.internalWebView
    }

    @objc func currentWinningBidJSON() -> String? {
        guard let bidResponse = adLoadFlowController?.bidResponse else {
            Log.debug("no bid response resolved yet")
            return nil
        }
        guard let winningBidDict = bidResponse.winningBid?.bid.jsonDictionary else {
            Log.debug("bid response has no winning bid yet")
            return nil
        }

        var responseDict = bidResponse.rawResponse?.jsonDictionary ?? [:]
        responseDict["seatbid"] = [["bid": [winningBidDict]]]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: responseDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Log.error("could not serialize the winning bid to JSON")
            return nil
        }
        return jsonString
    }

    /// The winning bid's creative ID, which is how a blocked creative is reported back.
    @objc func currentWinningBidCreativeId() -> String? {
        guard let creativeId = adLoadFlowController?.bidResponse?.winningBid?.bid.crid else {
            Log.debug("no winning bid resolved yet")
            return nil
        }
        return creativeId
    }

    /// The winning bid's targeting keys worth attributing a block to — currently the bidder.
    @objc func currentWinningBidCustomTargeting() -> [String: Any] {
        guard let hbBidder = adLoadFlowController?.bidResponse?.winningBid?.targetingInfo?["hb_bidder"] else {
            Log.debug("no hb_bidder in the winning bid's targeting")
            return [:]
        }
        return ["hb_bidder": hbBidder]
    }
}

#endif
