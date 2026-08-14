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

@testable import Life360AdsSDK

/// Covers the `ext.nativo` wire object: Nativo's ad server sets `ext.nativo` and `nativoAdType`, and
/// does not know or care that other parts of the SDK renamed themselves to `Life360` — a client-side
/// rename cannot change what the server sends, so `ORTBBidExt`/`ORTBBidExtNativo` keep those names.
class ORTBBidExtNativoTest: XCTestCase {

    /// A real bid response body, `ext` truncated to the field under test.
    private let bidExtJSON: [String: Any] = [
        "nativo": [
            "oo": 1,
            "nativoAdType": 0,
        ] as [String: Any],
    ]

    func testDecode_readsTheNativoWireKey() {
        let ext = ORTBBidExt(jsonDictionary: bidExtJSON)

        let nativo = ext.nativo
        XCTAssertNotNil(nativo, "ext.nativo did not decode")
        XCTAssertEqual(nativo?.isOwnedOperated, true)
        XCTAssertEqual(nativo?.adType, .article)
    }

    func testEncode_writesBackTheNativoWireKey() throws {
        let ext = ORTBBidExt(jsonDictionary: bidExtJSON)

        let reencoded = ext.jsonDictionary
        let nativo = try XCTUnwrap(reencoded["nativo"] as? [String: Any])
        XCTAssertEqual(nativo["oo"] as? NSNumber, 1)
        XCTAssertEqual(nativo["nativoAdType"] as? NSNumber, 0)
    }

    func testDecode_missingNativoKey_leavesNativoNil() {
        let ext = ORTBBidExt(jsonDictionary: [:])

        XCTAssertNil(ext.nativo)
    }
}
