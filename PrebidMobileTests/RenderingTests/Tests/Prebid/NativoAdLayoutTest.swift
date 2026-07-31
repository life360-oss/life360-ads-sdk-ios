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

@testable @_spi(PBMInternal) import Life360AdsSDK

/// Covers `NativoAdLayout`.
///
/// Deliberately avoids `WKWebView`: this test target has no host application, so a web view here is
/// slow and unreliable. `walkFirstChildChain` is generic over the stop type, so a marker `UIView`
/// subclass exercises identical logic.
class NativoAdLayoutTest: XCTestCase {

    private final class StopMarkerView: UIView {}

    // MARK: - expandChildren

    func testExpandChildren_appliesConstraints_whenCreativeSubviewPresent() {
        let banner = makeView()
        let displayView = makeView(in: banner)
        let creative = makeView(in: displayView)

        let result = NativoAdLayout.expandChildren(displayView, to: banner, withMinimum: 250)

        XCTAssertNoThrow(try result.get())
        XCTAssertTrue(
            banner.constraints.contains { isMatchConstraint($0, displayView, banner, .width) },
            "the DisplayView should be pinned to the banner's width"
        )
        XCTAssertTrue(
            banner.constraints.contains { isMatchConstraint($0, displayView, banner, .height) },
            "the DisplayView should be pinned to the banner's height"
        )
        XCTAssertTrue(
            displayView.constraints.contains {
                $0.firstAttribute == .height && $0.relation == .greaterThanOrEqual && $0.constant == 250
            },
            "the bid height should be applied as a floor"
        )
        // The creative itself is expanded too; its match constraints install on the DisplayView,
        // which is the nearest common ancestor.
        XCTAssertTrue(
            displayView.constraints.contains { isMatchConstraint($0, creative, displayView, .width) },
            "the creative should be expanded to fill the DisplayView"
        )
    }

    /// The match-height constraint must yield to the minimum, or a creative taller than the banner
    /// gets squashed instead of expanding it.
    func testExpandChildren_matchHeightYieldsToMinimum() {
        let banner = makeView()
        let displayView = makeView(in: banner)
        _ = makeView(in: displayView)

        NativoAdLayout.expandChildren(displayView, to: banner, withMinimum: 250)

        let matchHeight = banner.constraints.first { isMatchConstraint($0, displayView, banner, .height) }
        XCTAssertEqual(matchHeight?.priority, .defaultHigh)
    }

    /// A view deployed before its creative arrives has no child chain to expand. The caller has to be
    /// told, because the ad would otherwise sit silently at the raw bid size.
    func testExpandChildren_returnsMissingCreativeSubview_whenDeployedEmpty() {
        let banner = makeView()
        let displayView = makeView(in: banner)

        let result = NativoAdLayout.expandChildren(displayView, to: banner, withMinimum: 250)

        guard case .failure(let error) = result else {
            return XCTFail("expected .missingCreativeSubview when the DisplayView has no subviews")
        }
        XCTAssertEqual(error, .missingCreativeSubview)
    }

    // MARK: - expandFullWidth / expandFullHeight

    /// These must *replace* the parent's existing constraint for the view. Leaving the old one active
    /// puts two competing width constraints on the same view.
    func testExpandFullWidth_replacesExistingWidthConstraint_ratherThanStacking() {
        let parent = makeView()
        let child = makeView(in: parent)
        parent.widthAnchor.constraint(equalTo: child.widthAnchor).isActive = true

        NativoAdLayout.expandFullWidth(child)
        NativoAdLayout.expandFullWidth(child)

        let active = parent.constraints.filter {
            $0.isActive && ($0.firstAttribute == .width || $0.secondAttribute == .width)
                && (($0.firstItem as? UIView) === child || ($0.secondItem as? UIView) === child)
        }
        XCTAssertEqual(active.count, 1, "repeat calls must not leave competing width constraints")
    }

    func testExpandFullHeight_replacesExistingHeightConstraint_ratherThanStacking() {
        let parent = makeView()
        let child = makeView(in: parent)
        parent.heightAnchor.constraint(equalTo: child.heightAnchor).isActive = true

        NativoAdLayout.expandFullHeight(child)
        NativoAdLayout.expandFullHeight(child)

        let active = parent.constraints.filter {
            $0.isActive && ($0.firstAttribute == .height || $0.secondAttribute == .height)
                && (($0.firstItem as? UIView) === child || ($0.secondItem as? UIView) === child)
        }
        XCTAssertEqual(active.count, 1, "repeat calls must not leave competing height constraints")
    }

    func testExpandFullWidth_isNoOpWithoutSuperview() {
        let orphan = makeView()
        NativoAdLayout.expandFullWidth(orphan)
        XCTAssertTrue(orphan.constraints.isEmpty)
    }

    // MARK: - walkFirstChildChain

    /// The chain must be walked all the way down, because the creative sits several wrappers deep and
    /// any un-expanded wrapper clips the one below it.
    func testWalkFirstChildChain_visitsEveryViewDownToTheStopType() {
        let a = makeView()
        let b = makeView(in: a)
        let c = makeView(in: b)
        let stop = StopMarkerView()
        c.addSubview(stop)

        var visited: [UIView] = []
        NativoAdLayout.walkFirstChildChain(from: a, stopAtType: StopMarkerView.self) { visited.append($0) }

        XCTAssertEqual(visited, [a, b, c], "should visit the chain but not the stop view itself")
    }

    func testWalkFirstChildChain_visitsOnlyTheFirstChildBranch() {
        let root = makeView()
        let firstBranch = makeView(in: root)
        let secondBranch = makeView(in: root)

        var visited: [UIView] = []
        NativoAdLayout.walkFirstChildChain(from: root, stopAtType: StopMarkerView.self) { visited.append($0) }

        XCTAssertEqual(visited, [root, firstBranch])
        XCTAssertFalse(visited.contains(secondBranch))
    }

    // MARK: - applyNativoExpansion

    func testApplyNativoExpansion_expandsBannerAndReportsSuccess() {
        let container = makeView()
        let banner = makeView(in: container)
        let displayView = makeView(in: banner)
        _ = makeView(in: displayView)

        let result = NativoAdLayout.applyNativoExpansion(
            displayView: displayView,
            in: banner,
            minimumHeight: 250
        )

        XCTAssertNoThrow(try result.get())
        XCTAssertTrue(
            container.constraints.contains { isMatchConstraint($0, banner, container, .width) },
            "the banner should be expanded to fill its own container"
        )
        XCTAssertTrue(
            banner.constraints.contains { isMatchConstraint($0, displayView, banner, .width) },
            "the DisplayView should be expanded to fill the banner"
        )
    }

    func testApplyNativoExpansion_propagatesMissingCreativeSubview() {
        let container = makeView()
        let banner = makeView(in: container)
        let displayView = makeView(in: banner)

        let result = NativoAdLayout.applyNativoExpansion(
            displayView: displayView,
            in: banner,
            minimumHeight: 250
        )

        guard case .failure(let error) = result else {
            return XCTFail("expected the empty-DisplayView failure to reach the caller")
        }
        XCTAssertEqual(error, .missingCreativeSubview)
    }

    // MARK: - Helpers

    private func makeView(in parent: UIView? = nil) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
        view.translatesAutoresizingMaskIntoConstraints = false
        parent?.addSubview(view)
        return view
    }

    private func isMatchConstraint(
        _ constraint: NSLayoutConstraint,
        _ first: UIView,
        _ second: UIView,
        _ attribute: NSLayoutConstraint.Attribute
    ) -> Bool {
        constraint.firstAttribute == attribute
            && constraint.secondAttribute == attribute
            && constraint.relation == .equal
            && (((constraint.firstItem as? UIView) === first && (constraint.secondItem as? UIView) === second)
                || ((constraint.firstItem as? UIView) === second && (constraint.secondItem as? UIView) === first))
    }
}


/// `Bid.usesNativoRendering` is the single condition behind two decisions that must agree: whether
/// `NativoRendererInternal` expands the creative, and which delegate callback `BannerView` reports. Derived
/// separately, the two disagree on bids identified only by their loader script.
class BidNativoRenderingTest: XCTestCase {

    func testAdTypeWins_whenPresent() {
        XCTAssertTrue(makeBid(adType: .story, adm: "<html></html>").usesNativoRendering)
        XCTAssertTrue(makeBid(adType: .ctpVideo, adm: "<html></html>").usesNativoRendering)
    }

    /// Standard display is the one Nativo type that renders as an ordinary fixed-size banner.
    func testStandardDisplay_doesNotUseNativoRendering() {
        XCTAssertFalse(makeBid(adType: .standardDisplay, adm: "load.js").usesNativoRendering)
    }

    /// The markup fallback for bids that carry no adType. Both the renderer and `BannerView` have to honour
    /// it, or the publisher is told a plain banner loaded while the renderer expanded the view to fill its
    /// container.
    func testLoaderScriptFallback_whenAdTypeIsMissing() {
        XCTAssertTrue(makeBid(adType: nil, adm: "<script src='//x/load.js'></script>").usesNativoRendering)
        XCTAssertTrue(makeBid(adType: nil, adm: "<script src='//x/LOAD.JS'></script>").usesNativoRendering)
    }

    func testNoAdTypeAndNoLoaderScript_doesNotUseNativoRendering() {
        XCTAssertFalse(makeBid(adType: nil, adm: "<html><body>plain</body></html>").usesNativoRendering)
        XCTAssertFalse(makeBid(adType: nil, adm: nil).usesNativoRendering)
    }

    // MARK: - Helpers

    private func makeBid(adType: NativoAdType?, adm: String?) -> Bid {
        let rawBid = ORTBBid<ORTBBidExt>(bidID: "bid", impid: "imp", price: 1.0)
        rawBid.adm = adm
        if let adType {
            rawBid.ext = .init()
            rawBid.ext?.nativo = ORTBBidExtNativo(jsonDictionary: ["nativoAdType": NSNumber(value: adType.rawValue)])
        }
        return Bid(bid: rawBid)
    }
}
