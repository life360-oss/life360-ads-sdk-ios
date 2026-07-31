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

@testable @_spi(PBMInternal) import Life360AdsSDK

/// `Prebid.timeoutMillis` and `Prebid.timeoutMillisDynamic` both hold milliseconds, while
/// `PrebidServerConnection` feeds its `timeout` argument straight into `URLRequest.timeoutInterval`,
/// which is seconds. Reading the dynamic value without dividing turns the default 2000 ms budget
/// into a 2000-second one, so a stalled Nativo bid request would hang the ad load for ~33 minutes
/// instead of failing fast. These tests pin the conversion on both branches.
class NativoBidRequesterTimeoutTest: XCTestCase {

    private var sdkConfiguration: Prebid!
    private let targeting = Targeting.shared

    override func setUp() {
        super.setUp()
        sdkConfiguration = Prebid.mock
        sdkConfiguration.prebidServerAccountId = Prebid.devintAccountID
    }

    override func tearDown() {
        sdkConfiguration = nil
        super.tearDown()
    }

    /// The dynamic timeout is what the SDK reads in practice — `timeoutMillis`' setter mirrors
    /// itself into it, so it is never nil once an app configures a timeout.
    func testPostTimeoutConvertsDynamicMillisToSeconds() throws {
        sdkConfiguration.timeoutMillis = 2_000

        XCTAssertEqual(try capturedPostTimeout(), 2.0, accuracy: 0.001)
    }

    /// A non-default budget must scale the same way, not just the 2000 ms default.
    func testPostTimeoutConvertsNonDefaultDynamicMillisToSeconds() throws {
        sdkConfiguration.timeoutMillis = 750

        XCTAssertEqual(try capturedPostTimeout(), 0.75, accuracy: 0.001)
    }

    /// Control for the fallback branch: with no dynamic value, `timeoutMillis` is converted directly.
    func testPostTimeoutConvertsTimeoutMillisWhenDynamicUnset() throws {
        sdkConfiguration.timeoutMillis = 3_000
        sdkConfiguration.timeoutMillisDynamic = nil

        XCTAssertEqual(try capturedPostTimeout(), 3.0, accuracy: 0.001)
    }

    // MARK: - Helpers

    /// Drives a real `NativoBidRequester` against a mock connection and returns the `timeout`
    /// it handed to `post`, which is the value that reaches `URLRequest.timeoutInterval`.
    private func capturedPostTimeout(file: StaticString = #filePath, line: UInt = #line) throws -> TimeInterval {
        var postTimeout: TimeInterval?

        let connection = MockServerConnection(onPost: [{ (url, data, timeout, callback) in
            postTimeout = timeout
            callback(PrebidServerResponse())
        }])

        let requester = Factory.createNativoBidRequester(
            connection: connection,
            sdkConfiguration: sdkConfiguration,
            targeting: targeting,
            adUnitConfiguration: AdUnitConfig(configId: "config-id", size: CGSize(width: 300, height: 250))
        )

        let exp = expectation(description: "Nativo bid request completes")
        requester.requestBids { _, _ in exp.fulfill() }
        waitForExpectations(timeout: 5)

        return try XCTUnwrap(postTimeout, "NativoBidRequester never posted a bid request", file: file, line: line)
    }
}
