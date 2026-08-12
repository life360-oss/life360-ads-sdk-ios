//
//  BannerView+AppHarbr.swift
//
//  The banner details an ad quality scanner needs about the creative on screen right now.
//

import Foundation
import WebKit

internal extension BannerView {

    /// The web view the current creative renders into, or `nil` before a creative is set up.
    ///
    /// Follows ownership — display view to ad view manager to creative to its web view — rather than
    /// searching the view hierarchy, so the web view is available from `setupCreative` onward, which is
    /// before the creative's view is added to the display view. A scanner that wants to inspect a
    /// creative before it goes on screen needs it at that point.
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

    /// The bid response that produced the current creative, narrowed to the winning bid.
    ///
    /// Scanners match a creative against the bid that bought it, so the seatbid array is rewritten to
    /// hold the winner alone rather than every bid the auction returned.
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
