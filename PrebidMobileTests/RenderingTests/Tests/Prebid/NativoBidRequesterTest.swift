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

/// Covers the Nativo requester's request-timeout handling. Duplicate-callback behaviour lives in
/// `NativoBidRequesterCompletionTest`.
class NativoBidRequesterTest: XCTestCase {

    private var connection: DoubleFiringConnection!

    override func setUp() {
        super.setUp()
        connection = DoubleFiringConnection()
    }

    override func tearDown() {
        connection = nil
        Prebid.reset()
        super.tearDown()
    }

    /// `timeoutMillis` is milliseconds, but `PrebidServerConnection` applies its `timeout` to
    /// `URLRequest.timeoutInterval`, which is seconds. Passing the millisecond value through gives the
    /// request a deadline 1000x too long, so a lost response never surfaces as an error.
    func testRequestTimeout_isExpressedInSeconds() {
        Prebid.shared.timeoutMillis = 2000
        let requester = makeRequester()
        requester.requestBids { _, _ in }

        XCTAssertTrue(connection.postWasCalled)
        XCTAssertEqual(connection.capturedTimeout, 2.0, "2000 ms must reach the connection as 2 seconds")

        connection.fireStoredCallback()
    }

    // MARK: - Helpers

    private func makeRequester() -> BidRequesterProtocol {
        Factory.createNativoBidRequester(
            connection: connection,
            sdkConfiguration: Prebid.shared,
            targeting: Targeting.shared,
            adUnitConfiguration: AdUnitConfig(configId: "config-nativo", size: CGSize(width: 320, height: 50))
        )
    }
}

// MARK: - Test doubles

/// Captures the requester's callback so a test can deliver the same response more than once.
final class DoubleFiringConnection: NSObject, PrebidServerConnectionProtocol {

    private(set) var postWasCalled = false
    private(set) var capturedTimeout: TimeInterval?
    private var storedCallback: PrebidServerResponseCallback?

    var userAgentService: UserAgentService { .shared }

    func fireStoredCallback() {
        storedCallback?(Self.blankResponse())
    }

    func post(
        _ resourceURL: String?,
        data: Data?,
        timeout: TimeInterval,
        callback: @escaping PrebidServerResponseCallback
    ) {
        postWasCalled = true
        capturedTimeout = timeout
        storedCallback = callback
    }

    func post(
        _ resourceURL: String?,
        contentType: String?,
        data: Data?,
        timeout: TimeInterval,
        callback: @escaping PrebidServerResponseCallback
    ) {
        post(resourceURL, data: data, timeout: timeout, callback: callback)
    }

    func fireAndForget(_ resourceURL: String?) {}
    func head(_ resourceURL: String?, timeout: TimeInterval, callback: @escaping PrebidServerResponseCallback) {}
    func get(_ resourceURL: String?, timeout: TimeInterval, callback: @escaping PrebidServerResponseCallback) {}
    func download(_ resourceURL: String?, callback: @escaping PrebidServerResponseCallback) {}

    /// 204 is the cheapest terminal response: it needs no body and no JSON parsing.
    private static func blankResponse() -> PrebidServerResponse {
        let response = PrebidServerResponse()
        response.statusCode = 204
        return response
    }
}
