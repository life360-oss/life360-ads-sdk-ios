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

@testable import NativoPrebidSDK

class NativoBidResponseTest: XCTestCase {

    // MARK: - Helpers

    /// Creates a NativoBidResponse with a single Nativo bid at the given price and size.
    private func makeNativoBidResponse(price: Double, width: Int, height: Int) -> NativoBidResponse {
        let rawBid = ORTBBid<ORTBBidExt>(bidID: "test-bid-id", impid: "test-imp-id", price: NSNumber(value: price))
        rawBid.w = NSNumber(value: width)
        rawBid.h = NSNumber(value: height)

        let rawBidResponse = RawBidResponse(requestID: "test-request-id")
        rawBidResponse.seatbid = [.init(bid: [rawBid])]

        return NativoBidResponse(rawBidResponse: rawBidResponse)
    }

    // MARK: - Price formatting (hb_pb)

    /// Verifies that a whole-number price is formatted with two decimal places for GAM.
    /// e.g. 29.0 → "29.00", not "29.0"
    func testTargetingPriceFormattedWithTwoDecimalPlaces() {
        let response = makeNativoBidResponse(price: 29.0, width: 320, height: 50)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "29.00")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "29.00")
    }

    /// Verifies that an integer price (no fractional part) is formatted with two decimal places.
    /// e.g. 29 → "29.00", not "29" or "29.0"
    func testTargetingPriceIntegerFormattedWithTwoDecimalPlaces() {
        let response = makeNativoBidResponse(price: 29, width: 320, height: 50)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "29.00")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "29.00")
    }

    /// Verifies that a price already having two decimal digits retains them.
    func testTargetingPriceWithTwoDecimalDigits() {
        let response = makeNativoBidResponse(price: 1.50, width: 300, height: 250)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "1.50")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "1.50")
    }

    /// Verifies fractional cent pricing is rounded properly.
    func testTargetingPriceWithFractionalCents() {
        let response = makeNativoBidResponse(price: 3.456, width: 300, height: 250)

        XCTAssertEqual(response.targetingInfo?["hb_pb"], "3.46")
        XCTAssertEqual(response.targetingInfo?["hb_pb_nativo"], "3.46")
    }

    /// Verifies a zero-price bid does not become the winning bid (0 is not > 0),
    /// so no targeting info is set.
    func testTargetingPriceZeroDoesNotWin() {
        let response = makeNativoBidResponse(price: 0.0, width: 320, height: 50)

        XCTAssertNil(response.winningBid)
        XCTAssertTrue(response.targetingInfo?.isEmpty ?? true)
    }

    // MARK: - Size formatting (hb_size)

    /// Verifies that CGFloat-based dimensions are formatted as integers for GAM.
    /// e.g. 320.0x50.0 → "320x50", not "320.0x50.0"
    func testTargetingSizeFormattedAsIntegers() {
        let response = makeNativoBidResponse(price: 1.00, width: 320, height: 50)

        XCTAssertEqual(response.targetingInfo?["hb_size"], "320x50")
        XCTAssertEqual(response.targetingInfo?["hb_size_nativo"], "320x50")
    }

    /// Verifies a different common ad size formats correctly.
    func testTargetingSizeForMREC() {
        let response = makeNativoBidResponse(price: 2.00, width: 300, height: 250)

        XCTAssertEqual(response.targetingInfo?["hb_size"], "300x250")
        XCTAssertEqual(response.targetingInfo?["hb_size_nativo"], "300x250")
    }

    /// Verifies leaderboard ad size formats correctly.
    func testTargetingSizeForLeaderboard() {
        let response = makeNativoBidResponse(price: 5.00, width: 728, height: 90)

        XCTAssertEqual(response.targetingInfo?["hb_size"], "728x90")
        XCTAssertEqual(response.targetingInfo?["hb_size_nativo"], "728x90")
    }

    // MARK: - Static targeting keys

    /// Verifies all static targeting keys are present and correct.
    func testStaticTargetingKeys() {
        let response = makeNativoBidResponse(price: 10.0, width: 320, height: 50)
        let targeting = response.targetingInfo

        XCTAssertEqual(targeting?["hb_env"], "mobile-app")
        XCTAssertEqual(targeting?["hb_env_nativo"], "mobile-app")
        XCTAssertEqual(targeting?["hb_bidder"], "nativo")
        XCTAssertEqual(targeting?["hb_bidder_nativo"], "nativo")
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

        let response = NativoBidResponse(rawBidResponse: rawBidResponse)

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

        let response = NativoBidResponse(rawBidResponse: rawBidResponse)

        XCTAssertNil(response.winningBid)
        XCTAssertTrue(response.targetingInfo?.isEmpty ?? true)
    }
}
