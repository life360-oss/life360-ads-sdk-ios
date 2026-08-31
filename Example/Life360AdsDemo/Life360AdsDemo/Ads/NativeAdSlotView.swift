//
//  NativeAdSlotView.swift
//  Life360AdsDemoiOS
//

import UIKit
import Life360AdsSDK

/// A native ad slot.
///
/// Native uses Prebid's original API — `NativeRequest` returns a cached bid rather than a rendered
/// creative, and the app builds the layout. That also moves viewability measurement into the app's hands:
/// `NativeAd.registerView` starts the SDK's own IAB viewability timer against the view we hand it, and the
/// impression trackers only fire once that view has been at least half visible for a full second, which is
/// exactly the transition the surrounding feed is built to produce.
final class NativeAdSlotView: AdSlotView, NativeAdEventDelegate {

    /// Stored impression on the Prebid Server the app initialized against. This is the one slot that depends
    /// on it to fill: the original API is Prebid-Server-only, so an ID the server doesn't recognize surfaces
    /// as an error in the log rather than falling back to Nativo demand. The sample server under
    /// `prebid-server/sample/001_banner/stored_requests` ships banner-only impressions, so a native stored
    /// impression has to be added there — or point the app at the Life360 dev host.
    private static let configID = "test-imp-id-native"

    private let contentView = NativeAdContentView()
    private let placeholderLabel = UILabel()

    /// Retained so its viewability timer keeps running and its click handlers stay attached for as long as
    /// the slot exists. Dropping it would silently stop all native tracking.
    private var nativeAd: NativeAd?

    /// Retained for the same reason: `fetchDemand` is an instance method and the request dies with the
    /// ad unit.
    private var nativeRequest: NativeRequest?

    init() {
        super.init(logTag: "Native")
        setUpContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadAd() {
        super.loadAd()

        let request = NativeRequest(configId: Self.configID,
                                    assets: Self.requestedAssets,
                                    eventTrackers: Self.requestedEventTrackers)
        request.context = .Social
        request.placementType = .FeedContent
        request.placementCount = 1

        nativeRequest = request

        // Set this to enable native ad format responses without hb_cache_id for testing
        Prebid.shared.useCacheForReportingWithRenderingAPI = false

        report("fetchDemand sent — configID \(Self.configID)")

        request.fetchDemand { [weak self] bidInfo in
            guard let self else { return }

            guard bidInfo.resultCode == .prebidDemandFetchSuccess else {
                self.report("fetchDemand failed — \(bidInfo.resultCode.name())")
                return
            }

            guard let cacheId = bidInfo.nativeAdCacheId else {
                self.report("fetchDemand succeeded but returned no native cache id")
                return
            }

            guard let ad = NativeAd.create(cacheId: cacheId) else {
                self.report("bid was not a renderable native ad")
                return
            }

            self.render(ad)
        }
    }

    // MARK: - NativeAdEventDelegate

    func adDidLogImpression(ad: NativeAd) {
        report("adDidLogImpression — viewable for 1s, trackers fired")
    }

    func adWasClicked(ad: NativeAd) {
        report("adWasClicked")
    }

    func adDidExpire(ad: NativeAd) {
        report("adDidExpire — cached bid timed out")
    }

    // MARK: - Private

    /// Assets the demo asks for. All optional except the title so a partial-asset bid still renders
    /// something rather than being discarded.
    private static var requestedAssets: [NativeAsset] {
        let title = NativeAssetTitle(length: 90, required: true)

        let icon = NativeAssetImage(minimumWidth: 50, minimumHeight: 50, required: false)
        icon.type = ImageAsset.Icon

        let main = NativeAssetImage(minimumWidth: 300, minimumHeight: 200, required: false)
        main.type = ImageAsset.Main

        let sponsored = NativeAssetData(type: .sponsored, required: false)
        let body = NativeAssetData(type: .description, required: false)
        let cta = NativeAssetData(type: .ctatext, required: false)

        return [title, icon, main, sponsored, body, cta]
    }

    /// Impression trackers requested from the bidder. Image and JS methods are both advertised because a
    /// bidder that can't do one usually returns the other, and this app is here to watch them fire.
    private static var requestedEventTrackers: [NativeEventTracker] {
        [NativeEventTracker(event: EventType.Impression, methods: [EventTracking.Image, EventTracking.js])]
    }

    private func render(_ ad: NativeAd) {
        ad.delegate = self
        nativeAd = ad

        contentView.bind(ad)
        contentView.isHidden = false
        placeholderLabel.isHidden = true

        // The registered view is what the SDK measures for viewability, so it has to be the whole card —
        // registering a subview would report a smaller area than the user actually sees.
        let registered = ad.registerView(view: contentView, clickableViews: contentView.clickableViews)
        report("rendered — registerView \(registered ? "succeeded" : "failed")")
    }

    private func setUpContentView() {
        placeholderLabel.text = "Waiting for native demand…"
        placeholderLabel.font = .preferredFont(forTextStyle: .subheadline)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.textAlignment = .center
        placeholderLabel.heightAnchor.constraint(equalToConstant: 80).isActive = true

        contentView.isHidden = true

        // A stack view rather than two overlapping pinned children: a hidden arranged subview drops out of
        // the layout entirely, so the placeholder and the rendered card can each own the slot's height
        // without their constraints fighting during the swap.
        let stack = UIStackView(arrangedSubviews: [placeholderLabel, contentView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
