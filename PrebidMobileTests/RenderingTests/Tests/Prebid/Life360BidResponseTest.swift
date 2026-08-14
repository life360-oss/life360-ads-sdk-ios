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

@testable import Life360AdsSDK

class Life360BidResponseTest: XCTestCase {

    // MARK: - Helpers

    /// Creates a Life360BidResponse with a single Life360 bid at the given price and size.
    private func makeLife360BidResponse(price: Double, width: Int, height: Int) -> Life360BidResponse {
        let rawBid = ORTBBid<ORTBBidExt>(bidID: "test-bid-id", impid: "test-imp-id", price: NSNumber(value: price))
        rawBid.w = NSNumber(value: width)
        rawBid.h = NSNumber(value: height)

        let rawBidResponse = RawBidResponse(requestID: "test-request-id")
        rawBidResponse.seatbid = [.init(bid: [rawBid])]

        return Life360BidResponse(rawBidResponse: rawBidResponse)
    }

    // MARK: - Price formatting (hb_pb)

    /// Verifies that a whole-number price is formatted with two decimal places for GAM.
    /// e.g. 29.0 → "29.00", not "29.0"
    func testTargetingPriceFormattedWithTwoDecimalPlaces() {
        let response = makeLife360BidResponse(price: 29.0, width: 320, height: 50)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "29.00")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "29.00")
    }

    /// Verifies that an integer price (no fractional part) is formatted with two decimal places.
    /// e.g. 29 → "29.00", not "29" or "29.0"
    func testTargetingPriceIntegerFormattedWithTwoDecimalPlaces() {
        let response = makeLife360BidResponse(price: 29, width: 320, height: 50)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "29.00")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "29.00")
    }

    /// Verifies that a price already having two decimal digits retains them.
    func testTargetingPriceWithTwoDecimalDigits() {
        let response = makeLife360BidResponse(price: 1.50, width: 300, height: 250)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "1.50")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "1.50")
    }

    /// Verifies fractional cent pricing is rounded properly.
    func testTargetingPriceWithFractionalCents() {
        let response = makeLife360BidResponse(price: 3.456, width: 300, height: 250)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "3.46")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "3.46")
    }

    /// Verifies a zero-price bid does not become the winning bid (0 is not > 0),
    /// so no targeting info is set.
    func testTargetingPriceZeroDoesNotWin() {
        let response = makeLife360BidResponse(price: 0.0, width: 320, height: 50)

        XCTAssertNil(response.winningBid)
        XCTAssertTrue(response.targetingInfo?.isEmpty ?? true)
    }

    // MARK: - Size formatting (hb_size)

    /// Verifies that CGFloat-based dimensions are formatted as integers for GAM.
    /// e.g. 320.0x50.0 → "320x50", not "320.0x50.0"
    func testTargetingSizeFormattedAsIntegers() {
        let response = makeLife360BidResponse(price: 1.00, width: 320, height: 50)

        XCTAssertEqual(response.targetingInfo?["hb_size"], "320x50")
        XCTAssertEqual(response.targetingInfo?["hb_size_nativo"], "320x50")
    }

    /// Verifies a different common ad size formats correctly.
    func testTargetingSizeForMREC() {
        let response = makeLife360BidResponse(price: 2.00, width: 300, height: 250)

        XCTAssertEqual(response.targetingInfo?["hb_size"], "300x250")
        XCTAssertEqual(response.targetingInfo?["hb_size_nativo"], "300x250")
    }

    /// Verifies leaderboard ad size formats correctly.
    func testTargetingSizeForLeaderboard() {
        let response = makeLife360BidResponse(price: 5.00, width: 728, height: 90)

        XCTAssertEqual(response.targetingInfo?["hb_size"], "728x90")
        XCTAssertEqual(response.targetingInfo?["hb_size_nativo"], "728x90")
    }

    // MARK: - Static targeting keys

    /// Verifies all static targeting keys are present and correct.
    func testStaticTargetingKeys() {
        let response = makeLife360BidResponse(price: 10.0, width: 320, height: 50)
        let targeting = response.targetingInfo

        XCTAssertEqual(targeting?["hb_env"], "mobile-app")
        XCTAssertEqual(targeting?["hb_env_nativo"], "mobile-app")
        XCTAssertEqual(targeting?["hb_bidder"], "nativo")
        XCTAssertEqual(targeting?["hb_bidder_nativo"], "nativo")
    }

    /// The same targeting also has to be readable off the raw ORTB bid: anything that serializes the
    /// winning bid directly (an ad-quality scanner, a log) has no access to `targetingInfo`, only to
    /// `ORTBBid.jsonDictionary`, and that only sees what is under the bid's own `ext`.
    func testStaticTargetingKeys_areAlsoOnTheRawBidsExtPrebid() throws {
        let response = makeLife360BidResponse(price: 10.0, width: 320, height: 50)

        let prebidExt = try XCTUnwrap(response.winningBid?.bid.ext?.prebid)
        XCTAssertEqual(prebidExt.targeting?["hb_env"] as? String, "mobile-app")
        XCTAssertEqual(prebidExt.targeting?["hb_env_nativo"] as? String, "mobile-app")
        XCTAssertEqual(prebidExt.targeting?["hb_bidder"] as? String, "nativo")
        XCTAssertEqual(prebidExt.targeting?["hb_bidder_nativo"] as? String, "nativo")
        XCTAssertEqual(prebidExt.targeting?["hb_size"] as? String, "320x50")
        XCTAssertEqual(prebidExt.targeting?["hb_pb"] as? String, "10.00")

        // The same values reach a serialized copy of the bid — this is the property an ad-quality
        // scanner actually reads.
        let jsonDictionary = try XCTUnwrap(response.winningBid?.bid.jsonDictionary)
        let ext = try XCTUnwrap(jsonDictionary["ext"] as? [String: Any])
        let prebid = try XCTUnwrap(ext["prebid"] as? [String: Any])
        let targeting = try XCTUnwrap(prebid["targeting"] as? [String: Any])
        XCTAssertEqual(targeting["hb_bidder"] as? String, "nativo")
    }

    // MARK: - Winning bid selection

    /// Verifies the highest-priced bid is selected as the winning bid.
    func testWinningBidIsHighestPrice() {
        let bid1 = ORTBBid<ORTBBidExt>(bidID: "bid-1", impid: "imp-1", price: NSNumber(value: 5.0))
        bid1.w = NSNumber(value: 320)
        bid1.h = NSNumber(value: 50)

        let bid2 = ORTBBid<ORTBBidExt>(bidID: "bid-2", impid: "imp-1", price: NSNumber(value: 15.0))
        bid2.w = NSNumber(value: 300)
        bid2.h = NSNumber(value: 250)

        let rawBidResponse = RawBidResponse(requestID: "test-request-id")
        rawBidResponse.seatbid = [.init(bid: [bid1, bid2])]

        let response = Life360BidResponse(rawBidResponse: rawBidResponse)

        // Winning bid should be the higher-priced one
        XCTAssertEqual(response.winningBid?.price, Float(15.0))
        XCTAssertEqual(response.targetingInfo?["hb_pb"], "15.00")
        XCTAssertEqual(response.targetingInfo?["hb_size"], "300x250")
    }

    // MARK: - No bids

    /// Verifies that a response with no bids has no targeting info.
    func testNoBidsProducesNoTargeting() {
        let rawBidResponse = RawBidResponse(requestID: "test-request-id")
        rawBidResponse.seatbid = []

        let response = Life360BidResponse(rawBidResponse: rawBidResponse)

        XCTAssertNil(response.winningBid)
        XCTAssertTrue(response.targetingInfo?.isEmpty ?? true)
    }
}
