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

/// `PrebidMobilePluginRegister` stores renderers by *name*, so one `Life360RendererInternal` serves
/// every ad unit in the process. These tests pin the two invariants that follow: the renderer holds
/// **no per-load state**, and each `DisplayView` reaches its own loading delegate.
///
/// Renderer-level by design — no network, no web view, no flow controller — so routing is
/// deterministic rather than timing-dependent. `BannerViewConcurrencyTest` covers the full flow.
class Life360RendererConcurrencyTest: XCTestCase {

    private var renderer: Life360RendererInternal!
    private var interactionStub: StubInteractionDelegate!

    override func setUp() {
        super.setUp()
        renderer = Life360RendererInternal()
        interactionStub = StubInteractionDelegate()
    }

    override func tearDown() {
        renderer = nil
        interactionStub = nil
        super.tearDown()
    }

    // MARK: - Delegate wiring

    /// The caller's delegate must reach the DisplayView directly. A shared renderer standing in
    /// between would give every ad unit the same delegate.
    func testCreateBannerView_wiresLoadingDelegateDirectly_notSelf() {
        let spy = SpyLoadingDelegate()

        let view = makeBannerView(crid: "crid-A", width: 320, height: 50, loadingDelegate: spy)

        XCTAssertIdentical(
            view.loadingDelegate,
            spy,
            "DisplayView's loadingDelegate must be the caller's delegate, not the shared renderer"
        )
        XCTAssertFalse(
            view.loadingDelegate === renderer,
            "The shared renderer must not interpose itself as the per-view loading delegate"
        )
    }

    /// Two views from one renderer, each finishing its creative load: each delegate sees exactly its
    /// own view and nothing else.
    func testTwoConcurrentCreateBannerView_eachViewKeepsItsOwnDelegate() {
        let spyA = SpyLoadingDelegate()
        let spyB = SpyLoadingDelegate()

        let viewA = makeBannerView(crid: "crid-A", width: 320, height: 50, loadingDelegate: spyA)
        let viewB = makeBannerView(crid: "crid-B", width: 300, height: 250, loadingDelegate: spyB)

        // A's creative finishes after B exists — the interleaving a carousel produces.
        viewA.loadingDelegate?.displayViewDidLoadAd(viewA)
        viewB.loadingDelegate?.displayViewDidLoadAd(viewB)

        XCTAssertEqual(spyA.loadedViews.count, 1, "Slot A must be told about its own load exactly once")
        XCTAssertEqual(spyB.loadedViews.count, 1, "Slot B must be told about its own load exactly once")
        XCTAssertIdentical(spyA.loadedViews.first, viewA, "Slot A was given a different view")
        XCTAssertIdentical(spyB.loadedViews.first, viewB, "Slot B was given a different view")
    }

    /// Three views completing in creation order. Every delegate must be told about its own load;
    /// none may be told about a sibling's, and none may be left waiting.
    func testThreeConcurrentCreateBannerView_noSlotLosesItsCallback() {
        let spies = [SpyLoadingDelegate(), SpyLoadingDelegate(), SpyLoadingDelegate()]
        let views = [
            makeBannerView(crid: "crid-A", width: 320, height: 50, loadingDelegate: spies[0]),
            makeBannerView(crid: "crid-B", width: 300, height: 250, loadingDelegate: spies[1]),
            makeBannerView(crid: "crid-C", width: 728, height: 90, loadingDelegate: spies[2]),
        ]

        for view in views {
            view.loadingDelegate?.displayViewDidLoadAd(view)
        }

        for (index, spy) in spies.enumerated() {
            XCTAssertEqual(
                spy.loadedViews.count,
                1,
                "Slot \(index) got \(spy.loadedViews.count) load callbacks; expected exactly one, its own"
            )
            XCTAssertIdentical(spy.loadedViews.first, views[index], "Slot \(index) was given a different view")
        }
    }

    /// A failure on one ad unit must not be reported as a failure of another.
    func testFailureCallbackIsNotCrossRouted() {
        let spyA = SpyLoadingDelegate()
        let spyB = SpyLoadingDelegate()

        let viewA = makeBannerView(crid: "crid-A", width: 320, height: 50, loadingDelegate: spyA)
        let viewB = makeBannerView(crid: "crid-B", width: 300, height: 250, loadingDelegate: spyB)

        let error = NSError(domain: "test", code: 1)
        viewA.loadingDelegate?.displayView(viewA, didFailWithError: error)

        XCTAssertEqual(spyA.failedViews.count, 1, "Slot A's failure must be reported to slot A")
        XCTAssertIdentical(spyA.failedViews.first, viewA)
        XCTAssertTrue(spyB.failedViews.isEmpty, "Slot B must not be told about slot A's failure")

        // `DisplayView.loadingDelegate` is weak, so viewB has to stay alive for the assertions above
        // to mean anything.
        withExtendedLifetime(viewB) {}
    }

    // MARK: - Structural guard

    /// One renderer serves the whole process, so any stored per-load reference collapses every ad
    /// unit's callbacks into one. This fails the moment such a property is added.
    func testRendererHoldsNoPerLoadState() {
        let spy = SpyLoadingDelegate()
        _ = makeBannerView(crid: "crid-A", width: 320, height: 50, loadingDelegate: spy)

        let storedProperties = Mirror(reflecting: renderer!).children.compactMap { $0.label }
        let delegateLikeProperties = storedProperties.filter {
            $0.range(of: "delegate", options: .caseInsensitive) != nil
        }

        XCTAssertTrue(
            delegateLikeProperties.isEmpty,
            "Life360RendererInternal is a process-wide singleton and must not store per-load "
                + "delegates. Found: \(delegateLikeProperties). Route callbacks via the DisplayView "
                + "instead (see PrebidRenderer)."
        )
    }

    // MARK: - Helpers

    private func makeBannerView(
        crid: String,
        width: Int,
        height: Int,
        loadingDelegate: DisplayViewLoadingDelegate
    ) -> DisplayView {
        let bid = Life360BidFabricator.makeLife360Bid(
            price: 1.0,
            width: width,
            height: height,
            crid: crid
        )
        let size = CGSize(width: width, height: height)
        let config = AdUnitConfig(configId: "config-\(crid)", size: size)

        let view = renderer.createBannerView(
            with: CGRect(origin: .zero, size: size),
            bid: bid,
            adConfiguration: config,
            loadingDelegate: loadingDelegate,
            interactionDelegate: interactionStub
        )

        return view as! DisplayView
    }
}

// MARK: - Test doubles

/// Records which views it was told about, so a callback meant for another view is visible.
final class SpyLoadingDelegate: NSObject, DisplayViewLoadingDelegate {

    private(set) var loadedViews: [UIView] = []
    private(set) var failedViews: [UIView] = []
    private(set) var errors: [Error] = []

    func displayViewDidLoadAd(_ displayView: UIView) {
        loadedViews.append(displayView)
    }

    func displayView(_ displayView: UIView, didFailWithError error: Error) {
        failedViews.append(displayView)
        errors.append(error)
    }
}

final class StubInteractionDelegate: NSObject, DisplayViewInteractionDelegate {
    func trackImpression(forDisplayView: UIView) {}
    func didLeaveApp(from displayView: UIView) {}
    func willPresentModal(from displayView: UIView) {}
    func didDismissModal(from displayView: UIView) {}
    func viewControllerForModalPresentation(fromDisplayView: UIView) -> UIViewController? { nil }
}
