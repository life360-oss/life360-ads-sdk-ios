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

/// The requester's completion advances the ad load flow state machine, so it has to run exactly once
/// per request no matter how many times the network layer calls back.
class Life360BidRequesterCompletionTest: XCTestCase {

    private var connection: TwiceFiringConnection!

    override func setUp() {
        super.setUp()
        connection = TwiceFiringConnection()
    }

    override func tearDown() {
        connection = nil
        Prebid.reset()
        super.tearDown()
    }

    /// Redirects, retries and network-stack bugs can all deliver the same response twice. Invoking a
    /// completion that has already been taken and nil'd crashes rather than merely double-reporting.
    func testDuplicateNetworkCallback_invokesCompletionOnce() {
        let requester = makeRequester()

        var completionCount = 0
        let responded = expectation(description: "completion runs")
        requester.requestBids { _, _ in
            completionCount += 1
            responded.fulfill()
        }

        XCTAssertTrue(connection.postWasCalled, "the ORTB request should have reached the connection")
        connection.fireStoredCallbackTwice()

        wait(for: [responded], timeout: 1)
        XCTAssertEqual(completionCount, 1, "a duplicate network callback must not re-run the completion")
    }

    /// A second request on the same instance is refused rather than displacing the first, so the
    /// in-flight caller still gets its answer.
    func testSecondRequestWhileInFlight_isRejectedWithRequestInProgress() {
        let requester = makeRequester()

        var firstCompletionCount = 0
        requester.requestBids { _, _ in firstCompletionCount += 1 }

        let expected = PBMError.requestInProgress()
        let rejected = expectation(description: "second request is rejected")
        requester.requestBids { response, error in
            XCTAssertNil(response)
            XCTAssertEqual((error as NSError?)?.domain, expected.domain)
            XCTAssertEqual((error as NSError?)?.code, expected.code)
            rejected.fulfill()
        }

        wait(for: [rejected], timeout: 1)
        XCTAssertEqual(firstCompletionCount, 0, "the in-flight request must not have been completed yet")

        // Let the first request finish so the instance is not left holding a completion.
        connection.fireStoredCallback()
        XCTAssertEqual(firstCompletionCount, 1)
    }

    // MARK: - Helpers

    private func makeRequester() -> BidRequesterProtocol {
        Factory.createLife360BidRequester(
            connection: connection,
            sdkConfiguration: Prebid.shared,
            targeting: Targeting.shared,
            adUnitConfiguration: AdUnitConfig(configId: "config-life360-completion",
                                              size: CGSize(width: 320, height: 50))
        )
    }
}

// MARK: - Test doubles

/// Pre-populated so `UserAgentService` resolves without a web view.
private class SeededUserAgentPersistence: UserAgentPersistence {
    var userAgent: String?

    required init(osVersion: String? = nil) {}
}

/// Captures the requester's callback so a test can deliver the same response more than once.
///
/// File-private and distinctly named on purpose: sibling suites define their own connection doubles,
/// and a shared name at file scope would collide in this target.
private final class TwiceFiringConnection: NSObject, PrebidServerConnectionProtocol {

    private(set) var postWasCalled = false
    private var storedCallback: PrebidServerResponseCallback?

    /// A service seeded with a user agent, so the requester's warm-up completes synchronously.
    ///
    /// Never `.shared`: on a fresh simulator its user agent is empty, so the warm-up would go async
    /// through a `WKWebView` that cannot resolve in a host-less `xctest`, and the request would never
    /// be built. A cached user agent in `UserDefaults` masks that locally.
    let userAgentService: UserAgentService = {
        let store = SeededUserAgentPersistence(osVersion: nil)
        store.userAgent = "Mozilla/5.0 (test) Life360BidRequesterCompletionTest"
        return UserAgentService(store: store)
    }()

    func fireStoredCallback() {
        storedCallback?(Self.blankResponse())
    }

    /// Delivers the response twice, as a redirect or retry would.
    func fireStoredCallbackTwice() {
        fireStoredCallback()
        fireStoredCallback()
    }

    func post(
        _ resourceURL: String?,
        data: Data?,
        timeout: TimeInterval,
        callback: @escaping PrebidServerResponseCallback
    ) {
        postWasCalled = true
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
