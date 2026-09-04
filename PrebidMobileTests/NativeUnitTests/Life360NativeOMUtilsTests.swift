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
@testable import Life360AdsSDK

class Life360NativeOMUtilsTests: XCTestCase {

    private let scriptUrl = "https://verification.example.com/omid.js"

    // MARK: - Phase 1: event trackers

    func testEventTracker_JSMethodWithOMExtInEventTracker() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "eventtrackers": [
                ["event": 1, "method": 1, "url": "https://example.com/pixel.gif"],
                ["event": 1, "method": 2, "url": scriptUrl, "ext": [
                    "vendorKey": "vendor.com-omid",
                    "verificationParameters": "params-blob"
                ]]
            ]
        ])

        let resource = Life360NativeOMUtils.verificationResource(in: markup)

        XCTAssertEqual(resource, Life360NativeOMResource(url: scriptUrl,
                                                         vendorKey: "vendor.com-omid",
                                                         verificationParameters: "params-blob"))
    }

    func testEventTracker_ImageOnlyTrackersYieldNoResource() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "eventtrackers": [
                ["event": 1, "method": 1, "url": "https://example.com/pixel.gif"]
            ]
        ])

        XCTAssertNil(Life360NativeOMUtils.verificationResource(in: markup))
    }

    func testEventTracker_MissingVendorKeyYieldsNoResource() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "eventtrackers": [
                ["event": 1, "method": 2, "url": scriptUrl, "ext": [
                    "verificationParameters": "params-blob"
                ]]
            ]
        ])

        XCTAssertNil(Life360NativeOMUtils.verificationResource(in: markup))
    }

    func testEventTracker_SnakeCasedAndLowerCasedKeysResolve() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "eventtrackers": [
                ["event": 1, "method": 2, "ext": [
                    "omid_js_url": scriptUrl,
                    "vendor_key": "vendor.com-omid",
                    "verification_parameters": "params-blob"
                ]]
            ]
        ])

        XCTAssertEqual(Life360NativeOMUtils.verificationResource(in: markup)?.vendorKey, "vendor.com-omid")
    }

    func testEventTracker_FirstCompleteTrackerWins() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "eventtrackers": [
                // Incomplete: no parameters, so it must be skipped rather than aborting the search.
                ["event": 1, "method": 2, "url": scriptUrl, "ext": ["vendorKey": "incomplete"]],
                ["event": 1, "method": 2, "url": scriptUrl, "ext": [
                    "vendorKey": "complete",
                    "verificationParameters": "params-blob"
                ]]
            ]
        ])

        XCTAssertEqual(Life360NativeOMUtils.verificationResource(in: markup)?.vendorKey, "complete")
    }

    // MARK: - Phase 2: native.ext.omid

    func testExtOmid_SingleObject() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "ext": ["omid": [
                "resourceUrl": scriptUrl,
                "vendorKey": "vendor.com-omid",
                "params": "params-blob"
            ]]
        ])

        XCTAssertEqual(Life360NativeOMUtils.verificationResource(in: markup),
                       Life360NativeOMResource(url: scriptUrl,
                                               vendorKey: "vendor.com-omid",
                                               verificationParameters: "params-blob"))
    }

    func testExtOmid_ArrayOfObjects() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "ext": ["omid": [
                ["vendorKey": "incomplete"],
                ["url": scriptUrl, "vendor": "vendor.com-omid", "verificationParams": "params-blob"]
            ]]
        ])

        XCTAssertEqual(Life360NativeOMUtils.verificationResource(in: markup)?.vendorKey, "vendor.com-omid")
    }

    // MARK: - Phase 3: VAST-style AdVerifications

    func testExtAdVerifications() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "ext": ["adVerifications": ["verifications": [
                ["javascriptResourceUrl": scriptUrl,
                 "vendor": "vendor.com-omid",
                 "verificationParameters": "params-blob"]
            ]]]
        ])

        XCTAssertEqual(Life360NativeOMUtils.verificationResource(in: markup),
                       Life360NativeOMResource(url: scriptUrl,
                                               vendorKey: "vendor.com-omid",
                                               verificationParameters: "params-blob"))
    }

    func testExtVerificationsAtTopLevelOfExt() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "ext": ["verifications": [
                ["javascriptResourceUrl": scriptUrl,
                 "vendor": "vendor.com-omid",
                 "verificationParameters": "params-blob"]
            ]]
        ])

        XCTAssertNotNil(Life360NativeOMUtils.verificationResource(in: markup))
    }

    // MARK: - Phase ordering and rejection

    func testEventTrackersWinOverExt() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "eventtrackers": [
                ["event": 1, "method": 2, "url": scriptUrl, "ext": [
                    "vendorKey": "from-eventtrackers",
                    "verificationParameters": "params-blob"
                ]]
            ],
            "ext": ["omid": [
                "url": scriptUrl,
                "vendorKey": "from-ext",
                "params": "params-blob"
            ]]
        ])

        XCTAssertEqual(Life360NativeOMUtils.verificationResource(in: markup)?.vendorKey, "from-eventtrackers")
    }

    func testUrlWithoutHTTPSchemeIsRejected() {
        for url in ["not a url at all", "/relative/omid.js", "javascript:alert(1)"] {
            let markup = NativeAdMarkup(jsonDictionary: [
                "ext": ["omid": [
                    "url": url,
                    "vendorKey": "vendor.com-omid",
                    "params": "params-blob"
                ]]
            ])

            XCTAssertNil(Life360NativeOMUtils.verificationResource(in: markup),
                         "Expected \(url) to be rejected")
        }
    }

    func testEmptyStringsAreTreatedAsAbsent() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "ext": ["omid": [
                "url": scriptUrl,
                "vendorKey": "",
                "params": "params-blob"
            ]]
        ])

        XCTAssertNil(Life360NativeOMUtils.verificationResource(in: markup))
    }

    func testMarkupWithoutAnyOMDataYieldsNoResource() {
        let markup = NativeAdMarkup(jsonDictionary: [
            "link": ["url": "https://example.com/click"]
        ])

        XCTAssertNil(Life360NativeOMUtils.verificationResource(in: markup))
    }

    // MARK: - IAB compliance fixture

    /// A full `adm` carrying IAB's hosted validation-verification script, which is what an end-to-end
    /// check on device points at. If this and the extractor ever drift, the OM session silently never
    /// starts, which is slow to diagnose.
    func testIABValidationScriptFixtureYieldsResource() {
        let adm = #"""
        {"ver":"1.2","assets":[{"id":0,"title":{"text":"Prebid Server Native Ad"}},{"id":1,"img":{"type":1,"url":"https://picsum.photos/id/237/100/100","w":100,"h":100}},{"id":2,"img":{"type":3,"url":"https://picsum.photos/id/1015/600/400","w":600,"h":400}},{"id":3,"data":{"type":1,"value":"Sponsored by Prebid.org"}},{"id":4,"data":{"type":2,"value":"This is a test native ad served from the local Prebid Server sample stored response."}},{"id":5,"data":{"type":12,"value":"Learn More"}}],"link":{"url":"https://prebid.org"},"eventtrackers":[{"event":1,"method":1,"url":"https://example.com/imp-tracker.png"},{"event":1,"method":2,"url":"https://compliance.iabtechnologylab.com/compliance-js/omid-validation-verification-script-v1.js","ext":{"vendorKey":"iabtechlab.com-omid","verification_parameters":"unused-by-validation-script"}}]}
        """#

        guard let markup = NativeAdMarkup(jsonString: adm) else {
            return XCTFail("Fixture adm did not parse as native markup")
        }

        let resource = Life360NativeOMUtils.verificationResource(in: markup)

        XCTAssertEqual(resource?.url, "https://compliance.iabtechnologylab.com/compliance-js/omid-validation-verification-script-v1.js")
        // The validation script filters session events on this exact vendor key.
        XCTAssertEqual(resource?.vendorKey, "iabtechlab.com-omid")
        XCTAssertEqual(resource?.verificationParameters, "unused-by-validation-script")
    }
}
