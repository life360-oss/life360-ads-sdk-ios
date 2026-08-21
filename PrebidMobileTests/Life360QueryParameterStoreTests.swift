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

private let queryParametersUserDefaultsKey = Life360QueryParameterStore.customQueryParametersKey

class Life360QueryParameterStoreTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: queryParametersUserDefaultsKey)
        super.tearDown()
    }

    func testQueryParameters_ReadsValuesWrittenDirectlyToUserDefaults() {
        UserDefaults.standard.set(["config-id": ["foo": "bar", "baz": "qux"]], forKey: queryParametersUserDefaultsKey)

        XCTAssertEqual(Life360QueryParameterStore.queryParameters(forConfigId: "config-id"), ["foo": "bar", "baz": "qux"])
    }

    func testQueryParameters_DefaultsToEmptyWhenKeyNotSet() {
        XCTAssertEqual(Life360QueryParameterStore.queryParameters(forConfigId: "config-id"), [:])
    }

    func testQueryParameters_DefaultsToEmptyForAnUnrelatedConfigId() {
        UserDefaults.standard.set(["some-other-config-id": ["foo": "bar"]], forKey: queryParametersUserDefaultsKey)

        XCTAssertEqual(Life360QueryParameterStore.queryParameters(forConfigId: "config-id"), [:])
    }

    /// A dictionary containing any non-`String` value fails the `as? [String: String]` cast as a
    /// whole, dropping every entry for that `configId` rather than just the bad one — worth
    /// pinning since it's easy to assume the cast salvages the valid entries. Other `configId`s
    /// are unaffected since each is cast independently.
    func testQueryParameters_DropsEverythingForConfigIdWhenAnyValueIsNotAString() {
        let mixedParameters: [String: [String: Any]] = [
            "config-id": ["foo": 123],
            "some-other-config-id": ["foo": "bar"]
        ]
        UserDefaults.standard.set(mixedParameters, forKey: queryParametersUserDefaultsKey)

        XCTAssertEqual(Life360QueryParameterStore.queryParameters(forConfigId: "config-id"), [:])
        XCTAssertEqual(Life360QueryParameterStore.queryParameters(forConfigId: "some-other-config-id"), ["foo": "bar"])
    }
}
