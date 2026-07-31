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

import Foundation

class PrebidServerStatusRequester {
    
    /// Resolved per call rather than cached
    /// This enables users to switch between Life360Ads.initializeWithoutPrebid()
    /// and Prebid.initializeSDK() at runtime
    var serverEndpoint: String? {
        if let customStatusEndpoint {
            return customStatusEndpoint
        }

        guard let hostString = try? Host.shared.getHostURL(),
              let host = URL(string: hostString)?.host else {
            return nil
        }

        return PathBuilder.buildURL(for: host, path: PrebidConstants.SERVER_ENDPOINTS_STATUS)
    }

    /// Takes precedence over the host-derived endpoint once set.
    private var customStatusEndpoint: String?

    func setCustomStatusEndpoint(_ customStatusEndpoint: String?) {
        guard let customStatusEndpoint = customStatusEndpoint else { return }

        guard customStatusEndpoint.isValidURL() else {
            let endpointMessage = serverEndpoint == nil ? "There is no status endpoint to use." : "The '\(serverEndpoint ?? "")' endpoint will be used."
            Log.warn("The provided Prebid Server custom status endpoint is not valid. \(endpointMessage)")
            return
        }

        self.customStatusEndpoint = customStatusEndpoint
    }
    
    // MARK: - Internal Methods
    
    func requestStatus(_ completion: @escaping PrebidInitializationCallback) {
        guard Life360Ads.shared.prebidServerEnabled else {
            completion(.serverStatusSkipped, nil)
            return
        }

        guard !Prebid.shared.shouldDisableStatusCheck else {
            completion(.serverStatusSkipped, nil)
            return
        }
        
        guard let serverEndpoint = serverEndpoint else {
            completion(.serverStatusWarning, PBMError.error(description: "Life360 Ads SDK failed to get Prebid Server status endpoint."))
            return
        }
        
        PrebidServerConnection.shared.get(serverEndpoint) { serverResponse in
            guard serverResponse.isOKStatusCode else {
                completion(.serverStatusWarning, serverResponse.error ?? PBMError.error(description: "Error occured during Prebid Server status check."))
                return
            }
            
            completion(.succeeded, nil)
        }
    }
}
