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

import Foundation

@testable @_spi(PBMInternal) import Life360AdsSDK

/// Builds Life360 bid fixtures whose size and creative identity are *distinguishable* per slot.
///
/// The shared fixtures (`PBMBidResponseTransformer.someValidResponse`,
/// `WinningBidResponseFabricator`) hardcode one creative id and one 300x250 size, so they cannot
/// express "slot N received slot N's creative at slot N's size". Every value here derives from `crid`,
/// so a callback that reaches the wrong ad unit is visible in the assertion.
enum Life360BidFabricator {

    /// Self-contained markup: the creative must render with no network access, and must carry the
    /// creative id so a cross-routed load can be identified from the rendered view.
    static func adm(for crid: String) -> String {
        "<html><body><div id=\"\(crid)\">\(crid)</div></body></html>"
    }

    static func makeRawBid(
        price: Double,
        width: Int,
        height: Int,
        crid: String,
        adm markup: String? = nil,
        impId: String = "test-imp-id"
    ) -> ORTBBid<ORTBBidExt> {
        let rawBid = ORTBBid<ORTBBidExt>(
            bidID: "bid-\(crid)",
            impid: impId,
            price: NSNumber(value: price)
        )
        rawBid.w = NSNumber(value: width)
        rawBid.h = NSNumber(value: height)
        rawBid.crid = crid
        rawBid.adm = markup ?? adm(for: crid)
        return rawBid
    }

    static func makeLife360Bid(
        price: Double,
        width: Int,
        height: Int,
        crid: String,
        adm markup: String? = nil
    ) -> Life360Bid {
        Life360Bid(bid: makeRawBid(
            price: price,
            width: width,
            height: height,
            crid: crid,
            adm: markup
        ))
    }

    static func makeLife360BidResponse(
        price: Double,
        width: Int,
        height: Int,
        crid: String,
        adm markup: String? = nil
    ) -> Life360BidResponse {
        let rawBidResponse = RawBidResponse(requestID: "request-\(crid)")
        rawBidResponse.seatbid = [.init(bid: [makeRawBid(
            price: price,
            width: width,
            height: height,
            crid: crid,
            adm: markup
        )])]
        return Life360BidResponse(rawBidResponse: rawBidResponse)
    }

    /// A plain (non-Life360) `BidResponse`, so a test can mix renderers across concurrent slots.
    /// The bid resolves to `PrebidRenderer` because it carries no `meta.rendererName`.
    static func makePrebidBidResponse(
        price: Double,
        width: Int,
        height: Int,
        crid: String,
        adm markup: String? = nil
    ) -> BidResponse {
        let rawBidResponse = RawBidResponse(requestID: "request-\(crid)")
        let rawBid = makeRawBid(
            price: price,
            width: width,
            height: height,
            crid: crid,
            adm: markup
        )
        rawBid.ext = .init()
        rawBid.ext?.prebid = .init()
        rawBid.ext?.prebid?.type = "banner"
        // `Bid.isWinning` requires *both* hb_pb and hb_bidder; without them `BidResponse.createBids`
        // leaves `winningBid` nil and the flow never reaches the renderer.
        rawBid.ext?.prebid?.targeting = [
            "hb_pb": String(format: "%.2f", price),
            "hb_bidder": "test-bidder",
            "hb_size": "\(width)x\(height)",
        ]
        rawBidResponse.seatbid = [.init(bid: [rawBid])]
        return BidResponse(rawBidResponse: rawBidResponse)
    }
}
