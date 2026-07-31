/*   Copyright 2018-2023 Prebid.org, Inc.
 
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

class PrebidServerStatusRequesterTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        
        Prebid.reset()
    }
    
    override func tearDown() {
        super.tearDown()
        
        Prebid.reset()
    }
    
    func testURLValidation() {
        XCTAssertTrue("https://prebid-server-test-j.prebid.org/openrtb2/auction".isValidURL())
        XCTAssertTrue("http://www.google.com".isValidURL())
        XCTAssertTrue("http://stackoverflow.com".isValidURL())
        XCTAssertTrue("stackoverflow.com".isValidURL())
        XCTAssertTrue("http://127.0.0.1".isValidURL())
        XCTAssertTrue("http://127.0.0.1/status".isValidURL())
        
        XCTAssertFalse("123".isValidURL())
        XCTAssertFalse("/status".isValidURL())
    }
    
    func testStatusEndpoint_Default() {
        let testHost = "https://unique-prebid-server-host.org"
        try? Host.shared.setHostURL("\(testHost)/openrtb2/auction", nonTrackingURLString: nil)
        let requester = PrebidServerStatusRequester()
        
        let expectedStatusEndpoint = "\(testHost)/status/"
        XCTAssertTrue(requester.serverEndpoint == expectedStatusEndpoint)
    }
    
    func testStatusEndpoint_Nil() {
        let requester = PrebidServerStatusRequester()
        XCTAssertNil(requester.serverEndpoint)
        
        requester.requestStatus { status, error in
            XCTAssert(status == .serverStatusWarning)
            XCTAssertNotNil(error)
        }
    }
    
    func testSetCustomStatusEndpoint_Success() {
        let url = "https://prebid-server-test-j.prebid.org/openrtb2/auction"
        let requester = PrebidServerStatusRequester()
        
        requester.setCustomStatusEndpoint(url)
        
        XCTAssert(requester.serverEndpoint == url)
    }
    
    func testSetCustomStatusEndpoint_Failure() {
        let url = "/status"
        let requester = PrebidServerStatusRequester()
        
        requester.setCustomStatusEndpoint(url)
        
        XCTAssert(requester.serverEndpoint != url)
    }
    
    func testRequestStatus_Success() {
        try? Host.shared.setHostURL("https://prebid-server-test-j.prebid.org/openrtb2/auction", nonTrackingURLString: nil)
        
        let expectation = expectation(description: "Expected successful status response.")
        
        let requester = PrebidServerStatusRequester()
        
        requester.requestStatus { status, error in
            if case .succeeded = status {
                expectation.fulfill()
            }
            
            if let error = error {
                XCTFail("Failed with error: \(error.localizedDescription)")
            }
        }
        
        waitForExpectations(timeout: 3, handler: nil)
    }
    
    func testRequestStatus_ServerlessSkipped() {
        // Serverless init sets no Host URL; the status check must be skipped (not warned)
        // and must not hit the network.
        Life360Ads.shared.prebidServerEnabled = false

        let requester = PrebidServerStatusRequester()
        XCTAssertNil(requester.serverEndpoint)

        var didComplete = false
        requester.requestStatus { status, error in
            // Completes synchronously, before any network request.
            didComplete = true
            XCTAssertEqual(status, .serverStatusSkipped)
            XCTAssertNil(error)
        }

        XCTAssertTrue(didComplete, "requestStatus should complete synchronously without a network call.")
    }

    // `initializeWithoutPrebid()` sets no host, so a requester built then has no endpoint. A later
    // `Prebid.initializeSDK(serverURL:)` supplies one to that same long-lived requester, which must
    // pick it up rather than stay pinned to nil.
    func testStatusEndpoint_ResolvedAfterHostSetLater() {
        let requester = PrebidServerStatusRequester()
        XCTAssertNil(requester.serverEndpoint)

        let testHost = "https://unique-prebid-server-host.org"
        try? Host.shared.setHostURL("\(testHost)/openrtb2/auction", nonTrackingURLString: nil)

        XCTAssertEqual(requester.serverEndpoint, "\(testHost)/status/")
    }

    // A custom endpoint stays in force even if the host changes afterwards.
    func testStatusEndpoint_CustomEndpointOutranksHost() {
        let requester = PrebidServerStatusRequester()
        let custom = "https://custom-status.prebid.org/status"
        requester.setCustomStatusEndpoint(custom)

        try? Host.shared.setHostURL("https://some-other-host.org/openrtb2/auction", nonTrackingURLString: nil)

        XCTAssertEqual(requester.serverEndpoint, custom)
    }

    func testRequestSkipStatusCheck_Skipped() {
        Prebid.shared.shouldDisableStatusCheck = true
        
        try? Host.shared.setHostURL("https://prebid-server-test-j.prebid.org/openrtb2/auction", nonTrackingURLString: nil)
        
        let expectation = expectation(description: "Expected skipped status.")
        
        let requester = PrebidServerStatusRequester()
        
        requester.requestStatus { status, error in
            if case .serverStatusSkipped = status {
                expectation.fulfill()
            }
            
            if let error = error {
                XCTFail("Failed with error: \(error.localizedDescription)")
            }
        }
        
        waitForExpectations(timeout: 3, handler: nil)
    }
}
