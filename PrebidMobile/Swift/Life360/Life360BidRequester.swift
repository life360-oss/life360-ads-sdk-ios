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

import Foundation

/// Requests Life360 demand directly from the Life360 exchange, bypassing Prebid Server.
@objc(Life360BidRequester) @_spi(PBMInternal) public
class Life360BidRequester: NSObject, BidRequester {

    private typealias Completion = (BidResponse?, Error?) -> Void

    private static let baseURL = "https://exchange.postrelease.com/esi.json?ntv_epid=54"

    private let connection: PrebidServerConnectionProtocol
    private let sdkConfiguration: Prebid
    private let targeting: Targeting
    private let adUnitConfiguration: AdUnitConfig

    private let completionLock = NSLock()
    private var completion: Completion?

    public required init(
        connection: PrebidServerConnectionProtocol,
        sdkConfiguration: Prebid,
        targeting: Targeting,
        adUnitConfiguration: AdUnitConfig
    ) {
        self.connection = connection
        self.sdkConfiguration = sdkConfiguration
        self.targeting = targeting
        self.adUnitConfiguration = adUnitConfiguration
        super.init()
    }

    public func requestBids(completion: @escaping (BidResponse?, Error?) -> Void) {
        // The UA service resolves the user agent through a web view on the main thread, so building
        // the request first would put an empty device.ua on the first request of a session.
        connection.userAgentService.fetchUserAgent { [weak self] _ in
            self?.makeRequest(completion: completion)
        }
    }

    private func makeRequest(completion: @escaping Completion) {
        // Check and set under one lock, so two callers cannot both believe they own this request.
        guard claimSlot(for: completion) else {
            completion(nil, PBMError.requestInProgress())
            return
        }

        let requestString = buildORTBRequestString()
        guard !requestString.isEmpty else {
            takeCompletion()?(nil, PBMError.error(description: "Failed to build ORTB request"))
            return
        }

        // Both sources hold milliseconds; the connection wants seconds.
        let postTimeout = sdkConfiguration.timeoutMillisDynamic.map { $0.doubleValue / 1000.0 }
            ?? TimeInterval(sdkConfiguration.timeoutMillis) / 1000.0

        let url = Life360RequestURLBuilder.urlByAppendingCustomQueryParameters(
            to: Self.baseURL,
            forConfigId: adUnitConfiguration.configId
        )

        connection.post(url, data: requestString.data(using: .utf8), timeout: postTimeout) { [weak self] serverResponse in
            guard let self else { return }

            guard let completion = self.takeCompletion() else {
                // Redirects, retries and network-stack bugs can fire this callback more than once. The
                // completion advances the ad load flow state machine, so it must run exactly once.
                Log.info("Life360 bid callback invoked more than once. Ignoring the duplicate.")
                return
            }

            if serverResponse.statusCode == 204 {
                completion(nil, PBMError.blankResponse())
                return
            }

            if let error = serverResponse.error {
                completion(nil, error)
                return
            }

            completion(Life360BidResponse(jsonDictionary: serverResponse.jsonDict ?? [:]), nil)
        }
    }

    private func claimSlot(for newCompletion: @escaping Completion) -> Bool {
        completionLock.lock()
        defer { completionLock.unlock() }
        guard completion == nil else { return false }
        completion = newCompletion
        return true
    }

    /// Takes ownership of the pending completion, or returns nil if it has already been taken.
    private func takeCompletion() -> Completion? {
        completionLock.lock()
        defer { completionLock.unlock() }
        let taken = completion
        completion = nil
        return taken
    }

    private func buildORTBRequestString() -> String {
        let builders: [ParameterBuilder] = [
            PrebidParameterBuilder(
                adConfiguration: adUnitConfiguration,
                sdkConfiguration: sdkConfiguration,
                targeting: targeting,
                userAgentService: connection.userAgentService
            ),
            Life360ParameterBuilder(adConfiguration: adUnitConfiguration),
            Life360GeoLocationParameterBuilder(locationManager: .shared),
        ]

        let params = ParameterBuilderService.buildParamsDict(
            with: adUnitConfiguration.adConfiguration,
            extraParameterBuilders: builders
        )
        return params["openrtb"] ?? ""
    }
}
