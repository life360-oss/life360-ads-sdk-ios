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

/// Several `BannerView`s loading at once, as a carousel does. Each must report its own ad, at its own
/// size, exactly once.
///
/// Everything on the path is real — `AdLoadFlowController`, `BannerAdLoader`, the event handler,
/// plugin resolution, `NativoRendererInternal.createBannerView`, view deploy, and delegate reporting.
/// Two things are substituted:
///
/// 1. the two bid requesters, so each slot gets a *distinguishable* size and creative id;
/// 2. the creative render, because `xctest` has no host application and `WKWebView` cannot bring up
///    its networking/content process here (`Failed to resolve host network app id to config`).
///    The test fires the load callback through whatever delegate the renderer installed on the
///    `DisplayView`, which is the same hand-off the web view would trigger.
///
/// `NativoRendererConcurrencyTest` checks the same routing without a flow controller and is the
/// faster, fully deterministic version. This suite adds the full flow up to `BannerViewDelegate`.
class BannerViewConcurrencyTest: XCTestCase {

    private let flowTimeout: TimeInterval = 10

    private var recordingDelegate: RecordingBannerViewDelegate!
    private var collector: DisplayViewCollector!
    private var slots: [Slot] = []

    override func setUp() {
        super.setUp()
        recordingDelegate = RecordingBannerViewDelegate()
        collector = DisplayViewCollector()

        // The register keys renderers by name, so this mirrors production exactly: one instance per
        // renderer name, shared by every concurrently-loading slot.
        PrebidMobilePluginRegister.shared.unregisterAllPlugins()
        Prebid.registerPluginRenderer(CapturingPrebidRenderer(collector: collector))
        Prebid.registerPluginRenderer(CapturingNativoRenderer(collector: collector))
    }

    override func tearDown() {
        slots = []
        collector = nil
        recordingDelegate = nil
        PrebidMobilePluginRegister.shared.unregisterAllPlugins()
        Prebid.reset()
        super.tearDown()
    }

    // MARK: - Control

    /// Not a concurrency test. It proves the harness can drive one slot from `loadAd()` through the
    /// real flow to the publisher delegate, so that a failure below means something. If this fails,
    /// the harness is broken and the rest of the suite says nothing.
    func testSingleSlotLoads_control() {
        let slot = makeSlot(crid: "crid-solo", size: CGSize(width: 320, height: 50))
        slots = [slot]

        let reported = expectSuccess(for: slots)

        slot.bannerView.loadAd()
        let views = awaitDisplayViews(count: 1)
        views.forEach(finishCreativeLoad)

        wait(for: reported, timeout: flowTimeout)

        XCTAssertEqual(recordingDelegate.reportedSize(for: slot.bannerView), slot.size)
        XCTAssertEqual(deployedCreativeID(of: slot.bannerView), slot.crid)
    }

    // MARK: - Concurrent loads

    /// Three slots loaded concurrently: each reports its *own* size and deploys its *own* creative,
    /// exactly once.
    func testThreeConcurrentLoads_eachSlotReceivesItsOwnCreativeAndSize() {
        slots = makeThreeSlots()
        let reported = expectSuccess(for: slots)

        loadAllConcurrently()
        awaitDisplayViews(count: slots.count).forEach(finishCreativeLoad)

        wait(for: reported, timeout: flowTimeout)

        for slot in slots {
            XCTAssertEqual(
                recordingDelegate.reportedSize(for: slot.bannerView),
                slot.size,
                "Slot \(slot.crid) reported another slot's size"
            )
            XCTAssertEqual(
                deployedCreativeID(of: slot.bannerView),
                slot.crid,
                "Slot \(slot.crid) deployed another slot's creative"
            )
            XCTAssertEqual(
                recordingDelegate.successCount(for: slot.bannerView),
                1,
                "Slot \(slot.crid) reported success "
                    + "\(recordingDelegate.successCount(for: slot.bannerView)) times; "
                    + "it should hear about its own ad and nothing else"
            )
        }
    }

    /// The literal acceptance criterion: no slot may silently fail to return an ad.
    func testThreeConcurrentLoads_noSlotSilentlyFails() {
        slots = makeThreeSlots()
        let reported = expectSuccess(for: slots)

        let noFailures = expectation(description: "no slot reports a failure")
        noFailures.isInverted = true
        recordingDelegate.onFailure = { _, _ in noFailures.fulfill() }

        loadAllConcurrently()
        awaitDisplayViews(count: slots.count).forEach(finishCreativeLoad)

        wait(for: reported + [noFailures], timeout: flowTimeout)
    }

    /// One slot's creative finishes *before* the later slots exist, so any per-load state the shared
    /// renderer held would already have changed hands by the time the callback lands.
    func testStaggeredLoads_firstCreativeFinishesBeforeLaterSlotsAreCreated() {
        slots = makeThreeSlots()
        let reported = expectSuccess(for: slots)

        // Slot A alone first, so it completes while it is the only ad unit in flight.
        slots[0].bannerView.loadAd()
        let firstView = awaitDisplayViews(count: 1)[0]
        finishCreativeLoad(firstView)

        // Now B and C, created after A has already been told about its ad.
        slots[1].bannerView.loadAd()
        slots[2].bannerView.loadAd()
        awaitDisplayViews(count: 3).dropFirst().forEach(finishCreativeLoad)

        wait(for: reported, timeout: flowTimeout)

        for slot in slots {
            XCTAssertEqual(
                recordingDelegate.reportedSize(for: slot.bannerView),
                slot.size,
                "Staggered slot \(slot.crid) reported the wrong size"
            )
            XCTAssertEqual(
                recordingDelegate.successCount(for: slot.bannerView),
                1,
                "Staggered slot \(slot.crid) reported success more than once"
            )
        }
    }

    /// Routing must not depend on every slot resolving to the same renderer.
    func testConcurrentLoads_withMixedNativoAndPrebidWinners() {
        slots = [
            makeSlot(crid: "crid-nativo-A", size: CGSize(width: 320, height: 50)),
            makeSlot(crid: "crid-nativo-B", size: CGSize(width: 300, height: 250)),
            makeSlot(crid: "crid-prebid-C", size: CGSize(width: 728, height: 90), usePrebidRenderer: true),
        ]
        let reported = expectSuccess(for: slots)

        loadAllConcurrently()
        awaitDisplayViews(count: slots.count).forEach(finishCreativeLoad)

        wait(for: reported, timeout: flowTimeout)

        for slot in slots {
            XCTAssertEqual(
                recordingDelegate.reportedSize(for: slot.bannerView),
                slot.size,
                "Mixed slot \(slot.crid) reported the wrong size"
            )
        }
    }

    /// Calling `loadAd()` twice on one slot must not leave it reporting a stale ad or a stale size.
    func testRepeatedLoadAdOnSameSlot_isIdempotent() {
        let slot = makeSlot(crid: "crid-repeat", size: CGSize(width: 320, height: 50))
        slots = [slot]
        let reported = expectSuccess(for: slots, allowOverFulfill: true)

        slot.bannerView.loadAd()
        slot.bannerView.loadAd()

        awaitDisplayViews(count: 1, allowMore: true).forEach(finishCreativeLoad)
        wait(for: reported, timeout: flowTimeout)

        XCTAssertEqual(recordingDelegate.reportedSize(for: slot.bannerView), slot.size)
        XCTAssertEqual(deployedCreativeID(of: slot.bannerView), slot.crid)
    }

    // MARK: - Driving the flow

    private func loadAllConcurrently() {
        let banners = slots.map { $0.bannerView }
        DispatchQueue.concurrentPerform(iterations: banners.count) { index in
            banners[index].loadAd()
        }
    }

    /// Waits until the real flow has produced at least `count` `DisplayView`s.
    @discardableResult
    private func awaitDisplayViews(count: Int, allowMore: Bool = false) -> [DisplayView] {
        let created = expectation(description: "\(count) DisplayView(s) created by the real flow")
        created.assertForOverFulfill = false

        collector.onCreate = { [weak collector] in
            if (collector?.views.count ?? 0) >= count { created.fulfill() }
        }
        if collector.views.count >= count { created.fulfill() }

        wait(for: [created], timeout: flowTimeout)
        collector.onCreate = nil

        let views = collector.views
        if !allowMore {
            XCTAssertEqual(views.count, count, "unexpected number of DisplayViews created")
        }
        return views
    }

    /// Stands in for the web-view render: reports the ad as loaded through whatever delegate the
    /// renderer installed on this view.
    private func finishCreativeLoad(_ view: DisplayView) {
        view.loadingDelegate?.displayViewDidLoadAd(view)
    }

    /// Expectations are always created *before* the flow is driven, so a callback that arrives
    /// earlier than expected still counts.
    private func expectSuccess(
        for slots: [Slot],
        allowOverFulfill: Bool = false
    ) -> [XCTestExpectation] {
        let expectations = slots.map { slot -> XCTestExpectation in
            let exp = expectation(description: "slot \(slot.crid) reports success")
            exp.assertForOverFulfill = !allowOverFulfill
            return exp
        }
        let banners = slots.map { $0.bannerView }
        recordingDelegate.onSuccess = { bannerView, _ in
            guard let index = banners.firstIndex(where: { $0 === bannerView }) else { return }
            expectations[index].fulfill()
        }
        return expectations
    }

    // MARK: - Slot construction

    struct Slot {
        let bannerView: BannerView
        let crid: String
        let size: CGSize
    }

    private func makeThreeSlots() -> [Slot] {
        [
            makeSlot(crid: "crid-A", size: CGSize(width: 320, height: 50)),
            makeSlot(crid: "crid-B", size: CGSize(width: 300, height: 250)),
            makeSlot(crid: "crid-C", size: CGSize(width: 728, height: 90)),
        ]
    }

    /// Builds a real `BannerView` and swaps in a flow controller whose two bid requesters are
    /// per-slot stubs. `BannerView` stays both the flow delegate and the ad-loader delegate, so
    /// `loadAd()` still exercises the production path — this is an injection seam, not a bypass.
    private func makeSlot(
        crid: String,
        size: CGSize,
        price: Double = 1.0,
        usePrebidRenderer: Bool = false
    ) -> Slot {
        let bannerView = BannerView(
            frame: CGRect(origin: .zero, size: size),
            configID: "config-\(crid)",
            adSize: size,
            eventHandler: BannerEventHandlerStandalone()
        )

        // Only a *negative* value disables auto-refresh; 0 is clamped up to refreshIntervalMin (15).
        // The BannerView's AutoRefreshManager captured the original controller's queue, so leaving a
        // timer armed across the swap below would target a discarded controller.
        bannerView.refreshInterval = -1
        bannerView.delegate = recordingDelegate

        let response: BidResponse = usePrebidRenderer
            ? NativoBidFabricator.makePrebidBidResponse(
                price: price,
                width: Int(size.width),
                height: Int(size.height),
                crid: crid
            )
            : NativoBidFabricator.makeNativoBidResponse(
                price: price,
                width: Int(size.width),
                height: Int(size.height),
                crid: crid
            )

        let adLoader = BannerAdLoader(delegate: bannerView)
        bannerView.adLoadFlowController = AdLoadFlowController(
            // No Prebid Server demand, so the stubbed response is the only winner per slot.
            bidRequesterFactory: { _ in
                StubBidRequester(response: nil, error: PBMError.noWinningBid())
            },
            adLoader: adLoader,
            adUnitConfig: bannerView.adUnitConfig,
            delegate: bannerView,
            configValidationBlock: { _, _ in true },
            nativoBidRequesterFactory: { _ in
                StubBidRequester(response: response)
            }
        )

        return Slot(bannerView: bannerView, crid: crid, size: size)
    }

    /// The creative id carried by the view the BannerView actually deployed.
    private func deployedCreativeID(of bannerView: BannerView) -> String? {
        (bannerView.deployedView as? DisplayView)?.bid.bid.crid
    }
}

// MARK: - Test doubles

/// Collects the `DisplayView`s the flow creates, so the test can drive their load callbacks.
/// Only ever touched on the main queue (renderers create views inside `createPrebidAd`'s main hop).
final class DisplayViewCollector {

    private(set) var views: [DisplayView] = []
    var onCreate: (() -> Void)?

    func add(_ view: DisplayView) {
        // `DisplayView.loadAd()` returns immediately when a transaction factory already exists.
        // xctest has no host app, so WKWebView cannot load a creative here; skipping the render keeps
        // the flow from stalling and lets the test drive completion explicitly.
        view.transactionFactory = StubTransactionFactory()

        views.append(view)
        onCreate?()
    }
}

/// The shipped Nativo renderer plus a capture hook.
///
/// Subclassing rather than reimplementing is deliberate: `super.createBannerView` performs the real
/// delegate wiring under test, and because the register keys by the inherited `name`, this instance
/// is resolved for Nativo bids exactly as the shipped renderer would be.
final class CapturingNativoRenderer: NativoRendererInternal {

    private let collector: DisplayViewCollector

    init(collector: DisplayViewCollector) {
        self.collector = collector
        super.init()
    }

    override func createBannerView(
        with frame: CGRect,
        bid: Bid,
        adConfiguration: AdUnitConfig,
        loadingDelegate: DisplayViewLoadingDelegate,
        interactionDelegate: DisplayViewInteractionDelegate
    ) -> PrebidMobileDisplayViewProtocol? {
        let view = super.createBannerView(
            with: frame,
            bid: bid,
            adConfiguration: adConfiguration,
            loadingDelegate: loadingDelegate,
            interactionDelegate: interactionDelegate
        )
        if let displayView = view as? DisplayView {
            collector.add(displayView)
        }
        return view
    }
}

/// The stock renderer plus the same capture hook, so a mixed-renderer test can drive both slots.
final class CapturingPrebidRenderer: PrebidRenderer {

    private let collector: DisplayViewCollector

    init(collector: DisplayViewCollector) {
        self.collector = collector
        super.init()
    }

    override func createBannerView(
        with frame: CGRect,
        bid: Bid,
        adConfiguration: AdUnitConfig,
        loadingDelegate: DisplayViewLoadingDelegate,
        interactionDelegate: DisplayViewInteractionDelegate
    ) -> PrebidMobileDisplayViewProtocol? {
        let view = super.createBannerView(
            with: frame,
            bid: bid,
            adConfiguration: adConfiguration,
            loadingDelegate: loadingDelegate,
            interactionDelegate: interactionDelegate
        )
        if let displayView = view as? DisplayView {
            collector.add(displayView)
        }
        return view
    }
}

/// Present only so `DisplayView.loadAd()` short-circuits. It is never asked to load anything.
final class StubTransactionFactory: NSObject, TransactionFactory {

    override init() {
        super.init()
    }

    init(
        bid: Bid,
        adConfiguration: AdUnitConfig,
        connection: PrebidServerConnectionProtocol,
        callback: @escaping TransactionFactoryCallback
    ) {
        super.init()
    }

    func load(adMarkup: String) -> Bool { false }
}

/// Hands back one fixed response. Optionally delayed, so slots can be made to resolve out of order.
final class StubBidRequester: NSObject, BidRequesterProtocol {

    private let response: BidResponse?
    private let error: Error?
    private let delay: TimeInterval

    init(response: BidResponse?, error: Error? = nil, delay: TimeInterval = 0) {
        self.response = response
        self.error = error
        self.delay = delay
        super.init()
    }

    func requestBids(completion: @escaping (BidResponse?, Error?) -> Void) {
        guard delay > 0 else {
            completion(response, error)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [response, error] in
            completion(response, error)
        }
    }
}

/// Records what each `BannerView` was told, keyed by the view's identity.
///
/// The existing `BannerViewTest` delegate calls `XCTFail` on success because it only covers error
/// paths, so it cannot be reused here.
///
/// Conforms to `Life360BannerViewDelegate`, not just `BannerViewDelegate`: the Life360 callback is dispatched
/// by protocol conformance, so a delegate that merely implements the method never receives it and these
/// suites would only ever observe the standard callback.
final class RecordingBannerViewDelegate: NSObject, Life360BannerViewDelegate {

    var onSuccess: ((BannerView, CGSize) -> Void)?
    var onFailure: ((BannerView, Error) -> Void)?

    private let lock = NSLock()
    private var successes: [(view: BannerView, size: CGSize)] = []
    private var failures: [(view: BannerView, error: Error)] = []

    func bannerViewPresentationController() -> UIViewController? { nil }

    func bannerView(_ bannerView: BannerView, didReceiveAdWithAdSize adSize: CGSize) {
        record(bannerView, adSize)
    }

    func bannerView(_ bannerView: BannerView, didReceiveLife360AdWithSize adSize: CGSize) {
        record(bannerView, adSize)
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWith error: Error) {
        lock.withLock { failures.append((bannerView, error)) }
        onFailure?(bannerView, error)
    }

    // MARK: Queries

    func successCount(for bannerView: BannerView) -> Int {
        lock.withLock { successes.filter { $0.view === bannerView }.count }
    }

    func reportedSize(for bannerView: BannerView) -> CGSize? {
        lock.withLock { successes.first { $0.view === bannerView }?.size }
    }

    /// Every size reported to this view, in order, for tests that drive more than one load cycle.
    func reportedSizes(for bannerView: BannerView) -> [CGSize] {
        lock.withLock { successes.filter { $0.view === bannerView }.map(\.size) }
    }

    func failureCount(for bannerView: BannerView) -> Int {
        lock.withLock { failures.filter { $0.view === bannerView }.count }
    }

    // MARK: Private

    private func record(_ bannerView: BannerView, _ adSize: CGSize) {
        lock.withLock { successes.append((bannerView, adSize)) }
        onSuccess?(bannerView, adSize)
    }
}
