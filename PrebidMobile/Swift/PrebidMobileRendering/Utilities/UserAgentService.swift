/*   Copyright 2018-2021 Prebid.org, Inc.
 
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

import WebKit

@objc(PBMUserAgentService) @objcMembers
public class UserAgentService: NSObject {
    
    public static let shared = UserAgentService()

    /// Read while assembling bid requests, so read from every ad unit's request queue, while the web
    /// view below resolves it on the main thread. Backed by a lock rather than a `lazy var`, whose
    /// initialisation is not synchronised.
    public var userAgent: String {
        _userAgent.value
    }

    private let _userAgent: SynchronizedValue<String>
    private var store: UserAgentPersistence
    private var webViews = [WKWebView]()

    required init(store: UserAgentPersistence? = nil) {
        let resolvedStore = store ?? UserAgentDefaults()
        self.store = resolvedStore
        self._userAgent = SynchronizedValue(resolvedStore.userAgent ?? "")
        super.init()
        fetchUserAgent()
    }
    
    public func fetchUserAgent(completion: ((String) -> Void)? = nil) {
        // user agent has been already generated
        guard userAgent.isEmpty else {
            completion?(userAgent)
            return
        }
        
        DispatchQueue.main.async {
            let webView = WKWebView()
            self.webViews.append(webView)
            webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, error in
                guard let self = self else { return }
                
                if let error {
                    Log.error(error.localizedDescription)
                }
                
                // Claim-and-set in one step, so two in-flight fetches cannot both persist a value.
                let claimed: String? = self._userAgent.mutate { current in
                    guard current.isEmpty, let result else { return nil }
                    current = "\(result)"
                    return current
                }
                if let claimed {
                    store.userAgent = claimed
                }
                
                self.webViews.removeAll(where: { $0 == webView })
                
                completion?(self.userAgent)
            }
        }
    }
}
