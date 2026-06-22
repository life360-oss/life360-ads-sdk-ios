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
/// Nativo demand matches on the app bundle identifier, while Prebid demand matches
/// on the App Store (iTunes) ID when one is configured. These tests drive the same
/// `PBMParameterBuilderService` pipeline the SDK uses in production and pin both behaviours.
class NativoBundleFieldTest: XCTestCase {

    private let itunesID = "464700387"

    override func setUp() {
        super.setUp()
        UtilitiesForTesting.resetTargeting(.shared)
    }

    override func tearDown() {
        UtilitiesForTesting.resetTargeting(.shared)
        super.tearDown()
    }

    // MARK: - Nativo

    /// The Nativo builder must win over the itunesID the shared pipeline writes into `app.bundle`,
    /// so a Nativo request carries the app bundle identifier even when itunesID is configured.
    func testNativoSendsBundleIdentifierEvenWhenItunesIDSet() {
        Targeting.shared.itunesID = itunesID
        let mockBundle = MockBundle()

        let bidRequest = buildBidRequest(bundle: mockBundle, includeNativoBuilder: true)

        PBMAssertEq(bidRequest.app.bundle, mockBundle.mockBundleIdentifier)
        XCTAssertNotEqual(bidRequest.app.bundle, itunesID)
    }

    /// With no itunesID configured, a Nativo request still carries the app bundle identifier.
    func testNativoSendsBundleIdentifierWhenItunesIDUnset() {
        Targeting.shared.itunesID = nil
        let mockBundle = MockBundle()

        let bidRequest = buildBidRequest(bundle: mockBundle, includeNativoBuilder: true)

        PBMAssertEq(bidRequest.app.bundle, mockBundle.mockBundleIdentifier)
    }

    // MARK: - Prebid server

    /// When `Targeting.shared.itunesID` is set, Prebid server requests send it in `app.bundle`.
    func testPrebidSendsItunesIDWhenSet() {
        Targeting.shared.itunesID = itunesID

        let bidRequest = buildBidRequest(bundle: MockBundle(), includeNativoBuilder: false)

        PBMAssertEq(bidRequest.app.bundle, itunesID)
    }

    /// When `itunesID` is unset, Prebid server requests fall back to the app bundle identifier.
    func testPrebidFallsBackToBundleIdentifierWhenItunesIDUnset() {
        Targeting.shared.itunesID = nil
        let mockBundle = MockBundle()

        let bidRequest = buildBidRequest(bundle: mockBundle, includeNativoBuilder: false)

        PBMAssertEq(bidRequest.app.bundle, mockBundle.mockBundleIdentifier)
    }

    // MARK: - Helpers

    /// Drives the shared parameter-builder pipeline and parses the ORTB result. When
    /// `includeNativoBuilder` is true the Nativo builder is appended exactly as
    /// `NativoBidRequester.buildORTBRequestString` does, so the Nativo override is exercised end-to-end.
    private func buildBidRequest(bundle: PBMBundleProtocol, includeNativoBuilder: Bool) -> PBMORTBBidRequest {
        let extraBuilders: [PBMParameterBuilder]? = includeNativoBuilder
            ? [NativoParameterBuilder(adConfiguration: AdUnitConfig(configId: "config-id"), bundle: bundle)]
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
