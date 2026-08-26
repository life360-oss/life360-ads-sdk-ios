//
//  BannerAdSlotView.swift
//  Life360AdsDemoiOS
//

import UIKit
import Life360AdsSDK

/// A display banner slot — the whole integration, top to bottom: the ad unit, the view that hosts it, and
/// every delegate callback.
///
/// Deliberately standalone rather than sharing a base class with the video slot. The two overlap heavily,
/// but this app exists to show how each format is wired up, and that's worth more than the duplication is
/// worth avoiding — a reader shouldn't have to reassemble a banner integration out of a superclass.
final class BannerAdSlotView: AdSlotView, Life360BannerViewDelegate {

    /// Stored impression on the Prebid Server the app initialized against. This slot fills regardless of
    /// whether the server knows the ID, because Life360 demand is requested on its own path and ignores the
    /// stored impression.
    private static let configID = "nativo-imp-id"

    /// Size requested in the auction.
    private static let adSize = CGSize(width: 320, height: 50)

    /// Height reserved on screen, independent of the requested size. The Life360 renderer expands its
    /// creative to fill whatever the publisher gives it and treats the bid size only as a floor, so this is
    /// the knob for testing how a creative behaves in a container that doesn't match its bid.
    private static let containerHeight: CGFloat = 100

    /// Retained for the lifetime of the slot rather than rebuilt per appearance: the ad's OMSDK session and
    /// impression state live on this object, and scrolling it out of view is supposed to change its
    /// viewability — not destroy it.
    private var banner: BannerView?

    init() {
        super.init(logTag: "Banner")
        heightAnchor.constraint(equalToConstant: Self.containerHeight).isActive = true

        // Apply rounded corners to the slot container so embedded content respects the shape
        layer.cornerRadius = 12
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadAd() {
        super.loadAd()
        removeBanner()
        setTestingParameters()

        let banner = BannerView(frame: CGRect(origin: .zero, size: Self.adSize),
                                configID: Self.configID,
                                adSize: Self.adSize)
        banner.adFormat = .banner
        banner.delegate = self

        addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: topAnchor),
            banner.bottomAnchor.constraint(equalTo: bottomAnchor),
            banner.leadingAnchor.constraint(equalTo: leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        self.banner = banner
        banner.loadAd()
        report("request sent — configID \(Self.configID)")
    }

    // MARK: - Life360BannerViewDelegate

    func bannerViewPresentationController() -> UIViewController? {
        ViewHierarchy.presentingViewController(for: self)
    }

    func bannerView(_ bannerView: BannerView, didReceiveAdWithAdSize adSize: CGSize) {
        report("didReceiveAdWithAdSize \(formatted(adSize))")
    }

    func bannerView(_ bannerView: BannerView, didReceiveLife360AdWithSize adSize: CGSize) {
        report("didReceiveLife360AdWithSize \(formatted(adSize))")
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWith error: Error) {
        report("didFailToReceiveAdWith \(error.localizedDescription)")
    }

    func bannerViewDidDisplay(_ bannerView: BannerView) {
        report("bannerViewDidDisplay — impression tracked")
    }

    func bannerViewWillPresentModal(_ bannerView: BannerView) {
        report("bannerViewWillPresentModal")
    }

    func bannerViewDidDismissModal(_ bannerView: BannerView) {
        report("bannerViewDidDismissModal")
    }

    func bannerViewWillLeaveApplication(_ bannerView: BannerView) {
        report("bannerViewWillLeaveApplication")
    }

    // MARK: - Private
    
    private func setTestingParameters() {
        UserDefaults.standard.set(
            [Self.configID: ["ntv_tm": "tout"]],
            forKey: Life360QueryParameterStore.customQueryParametersKey
        )
    }

    private func removeBanner() {
        banner?.stopRefresh()
        banner?.removeFromSuperview()
        banner = nil
    }

    private func formatted(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }
}

