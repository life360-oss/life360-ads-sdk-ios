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

import XCTest
@testable import Life360AdsSDK

class PathBuildersTest: XCTestCase {
    
    func testBaseURKPathBuilderBase() {
        XCTAssertEqual(PathBuilder.buildURL(for: "d1"), "https://d1")
        XCTAssertEqual(PathBuilder.buildURL(for: ""), "https://")
        XCTAssertEqual(PathBuilder.buildURL(for: "😃"), "https://xn--h28h")
    }

    func testURLPathBuilderWithPath() {
        XCTAssertEqual(PathBuilder.buildURL(for: "d1", path: "/tt/"), "https://d1/tt/")
        XCTAssertEqual(PathBuilder.buildURL(for: "", path: "/ma/"), "https:///ma/")
        XCTAssertEqual(PathBuilder.buildURL(for: "😃", path: "/v/"), "https://xn--h28h/v/")
    }
    
    func testURLPathBuilderWithPathWithQuery() {
        XCTAssertEqual(PathBuilder.buildURL(for: "d1", path: "/tt/", queryItems: [
            URLQueryItem(name: "q", value: "v")
        ]), "https://d1/tt/?q=v")
    }
}
