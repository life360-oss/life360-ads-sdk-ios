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

/// Adds the fields the Life360 exchange matches on, on top of the shared Prebid request.
class Life360ParameterBuilder: NSObject, ParameterBuilder {

    private let adConfiguration: AdUnitConfig
    private let bundle: BundleProtocol

    init(adConfiguration: AdUnitConfig, bundle: BundleProtocol = Bundle.main) {
        self.adConfiguration = adConfiguration
        self.bundle = bundle
        super.init()
    }

    func build(_ bidRequest: ORTBBidRequest) {
        // Placement mapping.
        for imp in bidRequest.imp {
            imp.tagid = adConfiguration.configId
        }

        // Life360 demand matches on the app bundle identifier, so always send it here —
        // overriding any itunesID the shared pipeline placed in app.bundle for Prebid.
        if let bundleIdentifier = bundle.bundleIdentifier {
            bidRequest.app.bundle = bundleIdentifier
        }

        // Serializes to user.id; a nil value drops the key rather than sending an empty one.
        bidRequest.user.userid = Targeting.shared.publisherUserId
    }
}
