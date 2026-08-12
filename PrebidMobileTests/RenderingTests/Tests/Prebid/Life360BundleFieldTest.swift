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

/// SDK-1298: bidding partners need the right app identifier in `app.bundle`.
/// Life360 demand matches on the app bundle identifier, while Prebid demand matches
/// on the App Store (iTunes) ID when one is configured. These tests drive the same
/// `PBMParameterBuilderService` pipeline the SDK uses in production and pin both behaviours.
class Life360BundleFieldTest: XCTestCase {

    private let itunesID = "464700387"

    override func setUp() {
        super.setUp()
        UtilitiesForTesting.resetTargeting(.shared)
    }

    override func tearDown() {
        UtilitiesForTesting.resetTargeting(.shared)
        super.tearDown()
    }

    // MARK: - Life360

    /// The Life360 builder must win over the itunesID the shared pipeline writes into `app.bundle`,
    /// so a Life360 request carries the app bundle identifier even when itunesID is configured.
    func testLife360SendsBundleIdentifierEvenWhenItunesIDSet() {
        Targeting.shared.itunesID = itunesID
        let mockBundle = MockBundle()

        let bidRequest = buildBidRequest(bundle: mockBundle, includeLife360Builder: true)

        PBMAssertEq(bidRequest.app.bundle, mockBundle.mockBundleIdentifier)
        XCTAssertNotEqual(bidRequest.app.bundle, itunesID)
    }

    /// With no itunesID configured, a Life360 request still carries the app bundle identifier.
    func testLife360SendsBundleIdentifierWhenItunesIDUnset() {
        Targeting.shared.itunesID = nil
        let mockBundle = MockBundle()

        let bidRequest = buildBidRequest(bundle: mockBundle, includeLife360Builder: true)

        PBMAssertEq(bidRequest.app.bundle, mockBundle.mockBundleIdentifier)
    }

    // MARK: - Prebid server

    /// When `Targeting.shared.itunesID` is set, Prebid server requests send it in `app.bundle`.
    func testPrebidSendsItunesIDWhenSet() {
        Targeting.shared.itunesID = itunesID

        let bidRequest = buildBidRequest(bundle: MockBundle(), includeLife360Builder: false)

        PBMAssertEq(bidRequest.app.bundle, itunesID)
    }

    /// When `itunesID` is unset, Prebid server requests fall back to the app bundle identifier.
    func testPrebidFallsBackToBundleIdentifierWhenItunesIDUnset() {
        Targeting.shared.itunesID = nil
        let mockBundle = MockBundle()

        let bidRequest = buildBidRequest(bundle: mockBundle, includeLife360Builder: false)

        PBMAssertEq(bidRequest.app.bundle, mockBundle.mockBundleIdentifier)
    }

    // MARK: - Helpers

    /// Drives the shared parameter-builder pipeline and parses the ORTB result. When
    /// `includeLife360Builder` is true the Life360 builder is appended exactly as
    /// `Life360BidRequester.buildORTBRequestString` does, so the Life360 override is exercised end-to-end.
    private func buildBidRequest(bundle: PBMBundleProtocol, includeLife360Builder: Bool) -> PBMORTBBidRequest {
        let extraBuilders: [PBMParameterBuilder]? = includeLife360Builder
            ? [Life360ParameterBuilder(adConfiguration: AdUnitConfig(configId: "config-id"), bundle: bundle)]
            : nil

        let paramsDict = PBMParameterBuilderService.buildParamsDict(
            with: AdConfiguration(),
            bundle: bundle,
            pbmLocationManager: MockLocationManagerSuccessful.sharedMock,
            pbmDeviceAccessManager: MockDeviceAccessManager(rootViewController: nil),
            ctTelephonyNetworkInfo: MockCTTelephonyNetworkInfo(),
            reachability: MockReachability.shared,
            sdkConfiguration: Prebid.mock,
            sdkVersion: "MOCK_SDK_VERSION",
            targeting: Targeting.shared,
            extraParameterBuilders: extraBuilders
        )

        guard let strORTB = paramsDict[PrebidConstants.OPEN_RTB_SCHEME],
              let bidRequest = try? PBMORTBBidRequest.from(jsonString: strORTB) else {
            XCTFail("Failed to build ORTB bid request")
            return PBMORTBBidRequest()
        }
        return bidRequest
    }
}
