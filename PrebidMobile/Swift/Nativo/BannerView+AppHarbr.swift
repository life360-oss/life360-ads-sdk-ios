//
//  BannerView+AppHarbr.swift
//
//  The banner details an ad quality scanner needs about the creative on screen right now.
//

import Foundation
import WebKit

internal extension BannerView {

    /// The web view rendering the current creative, or `nil` before one is deployed.
    ///
    /// Walks the view hierarchy, so it is main-thread only. The caller is an ad quality scanner whose
    /// calling thread this SDK does not control, so an off-main call gives up the web view rather than
    /// reading UIKit state from the wrong thread — the bid is still reported, just without it.
    ///
    /// Deliberately not an `assert`, unlike the main-thread checks on this SDK's own API: a scanner
    /// calling from its own queue is not a caller bug to trap on, and trapping would leave the path
    /// that has to work in release builds untested.
    @objc func currentRenderingWebView() -> WKWebView? {
        guard Thread.isMainThread else {
            Log.error("currentRenderingWebView() called off the main thread; skipping the web view.")
            return nil
        }
        guard let deployedView else { return nil }

        return NativoUtils.firstWebView(in: deployedView)
    }

    /// The bid response that produced the current creative, narrowed to the winning bid.
    ///
    /// Scanners match a creative against the bid that bought it, so the seatbid array is rewritten to
    /// hold the winner alone rather than every bid the auction returned.
    @objc func currentWinningBidJSON() -> String? {
        guard let bidResponse = adLoadFlowController?.bidResponse,
              let winningBidDict = bidResponse.winningBid?.bid.jsonDictionary else {
            return nil
        }

        var responseDict = bidResponse.rawResponse?.jsonDictionary ?? [:]
        responseDict["seatbid"] = [["bid": [winningBidDict]]]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: responseDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    /// The winning bid's creative ID, which is how a blocked creative is reported back.
    @objc func currentWinningBidCreativeId() -> String? {
        adLoadFlowController?.bidResponse?.winningBid?.bid.crid
    }

    /// The winning bid's targeting keys worth attributing a block to — currently the bidder.
    @objc func currentWinningBidCustomTargeting() -> [String: Any] {
        var customTargeting: [String: Any] = [:]
        if let hbBidder = adLoadFlowController?.bidResponse?.winningBid?.targetingInfo?["hb_bidder"] {
            customTargeting["hb_bidder"] = hbBidder
        }
        return customTargeting
    }
}
