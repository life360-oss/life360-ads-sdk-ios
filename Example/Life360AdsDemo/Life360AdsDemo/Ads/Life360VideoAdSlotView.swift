//
//  Life360VideoAdSlotView.swift
//  Life360AdsDemoiOS
//

import UIKit
import Life360AdsSDK

/// A Life360 video ad with a banner ad format
final class Life360VideoAdSlotView: AdSlotView, Life360BannerViewDelegate {

    private static let configID = "nativo-video-tout-imp-id"

    /// Size requested in the auction.
    private static let adSize = CGSize(width: 300, height: 250)

    /// Height reserved on screen, independent of the requested size — see `BannerAdSlotView.slotHeight`.
    private static let containerHeight: CGFloat = 250

    /// Retained for the lifetime of the slot rather than rebuilt per appearance: the ad's OMSDK session and
    /// impression state live on this object, and scrolling it out of view is supposed to change its
    /// viewability — not destroy it.
    private var banner: BannerView?

    init() {
        super.init(logTag: "L360Video")
        heightAnchor.constraint(equalToConstant: Self.containerHeight).isActive = true
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
            [Self.configID: ["ntv_a": "442149", "ntv_tm": "tout"]],
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
