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

    // MARK: - AdQualityAdNetworkProtocol

    public var adNetworkVersion: String {
        PrebidConstants.VERSION
    }

    public func adNetworkAdapterName(for adFormat: AppHarbrSDK.AdFormat) -> String {
        // Not used for this flow — AppHarbr routes here explicitly via
        // AH.addBanner(with: .prebidLife360, ...), not by matching an adapter name.
        ""
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

        let webView = bannerView.currentRenderingWebView()
        if webView == nil {
            Log.debug("Life360AppHarbrQualityProvider: no current-creative webview found yet")
        }

        return AdQualityAdNetworkProperties(
            mediationAdUnitId: mediationAdUnitId,
            // Echoed back rather than hardcoded to banner: this is the format AppHarbr asked about,
            // and the cast above has already established that the object really is a banner.
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

#endif
