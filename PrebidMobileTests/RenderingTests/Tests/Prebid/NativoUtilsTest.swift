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
import WebKit

@testable @_spi(PBMInternal) import Life360AdsSDK

/// Covers `NativoUtils.firstWebView(in:)`.
///
/// The web views here are never asked to load anything: this target has no host application, so a
/// navigation would be slow and unreliable, while plain initialization is neither.
class NativoUtilsTest: XCTestCase {

    func testFirstWebView_findsANestedWebView() {
        let root = UIView()
        let creativeView = UIView()
        let webView = WKWebView()

        root.addSubview(creativeView)
        creativeView.addSubview(webView)

        XCTAssertIdentical(NativoUtils.firstWebView(in: root), webView)
    }

    func testFirstWebView_findsTheRootItself() {
        let webView = WKWebView()

        XCTAssertIdentical(NativoUtils.firstWebView(in: webView), webView)
    }

    func testFirstWebView_returnsNilWhenTheHierarchyHasNone() {
        let root = UIView()
        root.addSubview(UIView())
        root.subviews[0].addSubview(UIView())

        XCTAssertNil(NativoUtils.firstWebView(in: root))
    }

    func testFirstWebView_prefersTheEarlierSubtreeInDepthFirstOrder() {
        let root = UIView()
        let firstBranch = UIView()
        let expected = WKWebView()

        root.addSubview(firstBranch)
        firstBranch.addSubview(expected)
        root.addSubview(WKWebView())

        XCTAssertIdentical(NativoUtils.firstWebView(in: root), expected)
    }
}
