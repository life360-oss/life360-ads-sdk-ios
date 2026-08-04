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

/// Several ad units assembling ORTB requests at once while the host changes `Prebid.shared`.
///
/// `PBMPrebidParameterBuilder` reads `storedAuctionResponse` twice per build, `getStoredBidResponses()`
/// once, and `UserAgentService.userAgent` once — all on the calling ad unit's request queue. A plain
/// Swift `Dictionary` or `String` read while another thread writes it is memory-unsafe, not merely
/// stale, and the corruption surfaces later as an unrelated crash.
///
/// Ordinary assertions cannot see that; this exists to be run under Thread Sanitizer, which reports the
/// unsynchronised access itself. Passing without TSan only shows nothing crashed this time.
class SharedConfigConcurrencyTest: XCTestCase {

    private let concurrentBuilds = 8

    override func tearDown() {
        Prebid.reset()
        super.tearDown()
    }

    func testConcurrentOrtbBuilds_whileSharedConfigIsMutated() {
        let completed = expectation(description: "every build runs its completion")
        completed.expectedFulfillmentCount = concurrentBuilds

        // The flag is itself synchronised, so a race reported by TSan is the SDK's, not this test's.
        let keepWriting = SynchronizedValue(true)
        let writerFinished = expectation(description: "writer stops")

        DispatchQueue.global().async {
            var counter = 0
            while keepWriting.value {
                Prebid.shared.storedAuctionResponse = "stored-auction-\(counter)"
                Prebid.shared.addStoredBidResponse(bidder: "bidder-\(counter % 3)",
                                                   responseId: "response-\(counter)")
                if counter % 5 == 0 {
                    Prebid.shared.clearStoredBidResponses()
                }
                Prebid.shared.timeoutMillis = 1000 + (counter % 500)
                counter += 1
            }
            writerFinished.fulfill()
        }

        DispatchQueue.concurrentPerform(iterations: concurrentBuilds) { index in
            // A connection per iteration: sharing one would make the test double the racy party.
            let connection = DoubleFiringConnection()
            let requester = Factory.createNativoBidRequester(
                connection: connection,
                sdkConfiguration: Prebid.shared,
                targeting: Targeting.shared,
                adUnitConfiguration: AdUnitConfig(configId: "config-\(index)",
                                                  size: CGSize(width: 320, height: 50))
            )

            // Builds the ORTB body synchronously on this thread, which is the access under test.
            requester.requestBids { _, _ in completed.fulfill() }

            // Completes the request if the build got as far as the connection.
            connection.fireStoredCallback()
        }

        wait(for: [completed], timeout: 60)
        keepWriting.value = false
        wait(for: [writerFinished], timeout: 10)
    }

    /// The same shape for the one global that is read on every request but resolved on the main thread.
    func testConcurrentUserAgentReads_whileItIsBeingResolved() {
        let service = UserAgentService()
        let read = expectation(description: "every reader finishes")
        read.expectedFulfillmentCount = concurrentBuilds

        let resolved = expectation(description: "the user agent resolves")
        resolved.assertForOverFulfill = false
        service.fetchUserAgent { _ in resolved.fulfill() }

        DispatchQueue.concurrentPerform(iterations: concurrentBuilds) { _ in
            for _ in 0..<200 {
                _ = service.userAgent
            }
            read.fulfill()
        }

        wait(for: [read, resolved], timeout: 30)
    }
}

/// A connection that captures the requester's callback instead of hitting the network.
///
/// File-private: sibling suites define their own connection doubles, and a shared name at file scope
/// would collide in this target.
/// Pre-populated so `UserAgentService` resolves without a web view.
private class SeededUserAgentPersistence: UserAgentPersistence {
    var userAgent: String?

    required init(osVersion: String? = nil) {}
}

private final class DoubleFiringConnection: NSObject, PrebidServerConnectionProtocol {

    private(set) var postWasCalled = false
    private(set) var capturedTimeout: TimeInterval?
    private var storedCallback: PrebidServerResponseCallback?

    /// Seeded, so a request never waits on a `WKWebView`. `.shared` starts with an empty user agent on
    /// a clean machine; once the requester warms the service before building, that would leave every
    /// build here waiting on a web view that cannot resolve in a host-less `xctest`. A cached value in
    /// `UserDefaults` masks it locally.
    let userAgentService: UserAgentService = {
        let store = SeededUserAgentPersistence(osVersion: nil)
        store.userAgent = "Mozilla/5.0 (test) SharedConfigConcurrencyTest"
        return UserAgentService(store: store)
    }()

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
