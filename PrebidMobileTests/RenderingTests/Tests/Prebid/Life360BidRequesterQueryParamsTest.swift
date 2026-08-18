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

@testable @_spi(PBMInternal) import Life360AdsSDK

/// `Life360BidRequester` posts to a URL literal hardcoded in `-makeRequestWithCompletion:`. These
/// tests pin that query parameters written directly to `UserDefaults` (the documented internal
/// contract — see `Life360QueryParameterStore`) end up appended to that URL, and that they can
/// never clobber the fixed `ntv_epid` parameter.
class Life360BidRequesterQueryParamsTest: XCTestCase {

    /// Must match the literal key documented for internal app engineers — see
    /// `Life360QueryParameterStoreTests` for why this is a hardcoded string, not a Swift symbol.
    private let queryParametersUserDefaultsKey = Life360QueryParameterStore.customQueryParametersKey

    private var sdkConfiguration: Prebid!
    private let targeting = Targeting.shared

    override func setUp() {
        super.setUp()
        sdkConfiguration = Prebid.mock
        sdkConfiguration.prebidServerAccountId = Prebid.devintAccountID
    }

    override func tearDown() {
        sdkConfiguration = nil
        UserDefaults.standard.removeObject(forKey: queryParametersUserDefaultsKey)
        super.tearDown()
    }

    func testCustomQueryParameterIsAppendedToPostedURL() throws {
        UserDefaults.standard.set(["publisher_id": "abc123"], forKey: queryParametersUserDefaultsKey)

        let url = try capturedPostURL()

        XCTAssertTrue(url.contains("publisher_id=abc123"))
    }

    func testMultipleCustomQueryParametersAreAppendedInSortedOrder() throws {
        UserDefaults.standard.set(["b": "2", "a": "1"], forKey: queryParametersUserDefaultsKey)

        let url = try capturedPostURL()

        XCTAssertTrue(url.hasSuffix("&a=1&b=2"))
    }

    func testCustomQueryParameterCannotOverrideFixedParameter() throws {
        UserDefaults.standard.set(["ntv_epid": "999"], forKey: queryParametersUserDefaultsKey)

        let url = try capturedPostURL()

        XCTAssertTrue(url.contains("ntv_epid=54"))
        XCTAssertFalse(url.contains("ntv_epid=999"))
    }

    func testNoCustomQueryParametersLeavesURLUnchanged() throws {
        let url = try capturedPostURL()

        XCTAssertEqual(url, "https://exchange.postrelease.com/esi.json?ntv_epid=54")
    }

    // MARK: - Helpers

    /// Drives a real `Life360BidRequester` against a mock connection and returns the URL string
    /// it handed to `post`.
    private func capturedPostURL(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        var postURL: String?

        let connection = MockServerConnection(onPost: [{ (url, data, timeout, callback) in
            postURL = url
            callback(PrebidServerResponse())
        }])

        let requester = Factory.createLife360BidRequester(
            connection: connection,
            sdkConfiguration: sdkConfiguration,
            targeting: targeting,
            adUnitConfiguration: AdUnitConfig(configId: "config-id", size: CGSize(width: 300, height: 250))
        )

        let exp = expectation(description: "Life360 bid request completes")
        requester.requestBids { _, _ in exp.fulfill() }
        waitForExpectations(timeout: 5)

        return try XCTUnwrap(postURL, "Life360BidRequester never posted a bid request", file: file, line: line)
    }
}
