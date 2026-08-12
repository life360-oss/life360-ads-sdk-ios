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

/// `device.ua` comes from `UserAgentService`, which resolves the value through a web view on the main
/// thread. The request body therefore has to be built *after* the service has been given a chance to
/// resolve, or the first Life360 request of a session carries an empty user agent.
///
/// The service is reached through the connection rather than the shared singleton, so a test can supply
/// one that never touches `WKWebView`.
class Life360BidRequesterUserAgentTest: XCTestCase {

    private let knownUserAgent = "Mozilla/5.0 (test) Life360BidRequesterUserAgentTest"

    private var userAgentService: DeferredUserAgentService!
    private var connection: RecordingConnection!

    override func setUp() {
        super.setUp()
        let store = StubUserAgentPersistence(osVersion: nil)
        store.userAgent = knownUserAgent
        userAgentService = DeferredUserAgentService(store: store)
        userAgentService.resetCounters()
        connection = RecordingConnection(userAgentService: userAgentService)
    }

    override func tearDown() {
        connection = nil
        userAgentService = nil
        Prebid.reset()
        super.tearDown()
    }

    /// The load-bearing assertion: nothing is sent until the user agent has resolved.
    func testRequest_waitsForTheUserAgentBeforeBuildingTheBody() {
        let requester = makeRequester()

        requester.requestBids { _, _ in }

        XCTAssertEqual(userAgentService.fetchCallCount, 1, "the requester should ask for the user agent")
        XCTAssertFalse(
            connection.postWasCalled,
            "the body must not be built until the user agent resolves, or device.ua goes out empty"
        )

        userAgentService.resolvePending()

        XCTAssertTrue(connection.postWasCalled, "the request should be sent once the user agent resolves")
    }

    /// That the value reaches the wire at all. Not a regression lock — the stub store is seeded, so
    /// `userAgent` is non-empty from the start and this passes with or without the warm-up. Pinning the
    /// empty-store case would need `UserAgentService.userAgent` to be settable from a subclass, which it
    /// deliberately is not.
    func testRequest_carriesTheUserAgentInDeviceUa() throws {
        let requester = makeRequester()
        requester.requestBids { _, _ in }
        userAgentService.resolvePending()

        let body = try XCTUnwrap(connection.postedBody, "no request body was captured")
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any],
            "the ORTB body should be JSON"
        )
        let device = try XCTUnwrap(json["device"] as? [String: Any], "the ORTB body should carry a device object")

        XCTAssertEqual(device["ua"] as? String, knownUserAgent)
    }

    // MARK: - Helpers

    private func makeRequester() -> BidRequesterProtocol {
        Factory.createLife360BidRequester(
            connection: connection,
            sdkConfiguration: Prebid.shared,
            targeting: Targeting.shared,
            adUnitConfiguration: AdUnitConfig(configId: "config-life360-ua",
                                              size: CGSize(width: 320, height: 50))
        )
    }
}

// MARK: - Test doubles

private class StubUserAgentPersistence: UserAgentPersistence {
    var userAgent: String?

    required init(osVersion: String? = nil) {}
}

/// Holds the fetch completion so a test can decide exactly when the user agent resolves, and never
/// creates a `WKWebView` — this target has no host application, so a real resolve is unreliable here.
private final class DeferredUserAgentService: UserAgentService {

    private(set) var fetchCallCount = 0
    private var pendingCompletion: ((String) -> Void)?

    required init(store: UserAgentPersistence? = nil) {
        super.init(store: store)
    }

    override func fetchUserAgent(completion: ((String) -> Void)? = nil) {
        fetchCallCount += 1
        pendingCompletion = completion
    }

    /// `UserAgentService.init` calls `fetchUserAgent`, so the count has to be zeroed after construction
    /// for a test to measure only what the requester did.
    func resetCounters() {
        fetchCallCount = 0
    }

    func resolvePending() {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(userAgent)
    }
}

/// Records the posted body and hands back the injected user agent service.
private final class RecordingConnection: NSObject, PrebidServerConnectionProtocol {

    private(set) var postWasCalled = false
    private(set) var postedBody: Data?

    private let injectedUserAgentService: UserAgentService

    var userAgentService: UserAgentService { injectedUserAgentService }

    init(userAgentService: UserAgentService) {
        self.injectedUserAgentService = userAgentService
        super.init()
    }

    func post(
        _ resourceURL: String?,
        data: Data?,
        timeout: TimeInterval,
        callback: @escaping PrebidServerResponseCallback
    ) {
        postWasCalled = true
        postedBody = data
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
}
