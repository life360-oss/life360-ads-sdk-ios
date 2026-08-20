//
//  VideoAdSlotView.swift
//  Life360AdsDemoiOS
//

import UIKit
import Life360AdsSDK

/// An outstream (in-feed) video slot — the whole integration, top to bottom.
///
/// Outstream rather than interstitial or rewarded because the point is to scroll the ad in and out of view:
/// the SDK starts and pauses playback on viewability, so the video quartile trackers and the OMSDK video
/// events only fire the way production does when the player can leave the viewport.
///
/// Standalone rather than sharing a base class with the banner slot — see `BannerAdSlotView` for why.
final class VideoAdSlotView: AdSlotView, Life360BannerViewDelegate, BannerViewVideoPlaybackDelegate {

    /// Stored impression on the Prebid Server the app initialized against. The sample server under
    /// `prebid-server/sample/001_banner/stored_requests` ships banner-only impressions, so a real VAST bid
    /// needs a video stored impression added there — until then this slot fills with whatever Life360
    /// returns, which is requested on its own path and ignores the stored impression entirely.
    private static let configID = "test-imp-id-video"

    /// Size requested in the auction.
    private static let adSize = CGSize(width: 300, height: 250)

    /// Height reserved on screen, independent of the requested size — see `BannerAdSlotView.slotHeight`.
    private static let slotHeight: CGFloat = 250

    /// Retained for the lifetime of the slot rather than rebuilt per appearance: the ad's OMSDK session,
    /// impression state, and video position all live on this object, and scrolling it out of view is
    /// supposed to change its viewability — not destroy it.
    private var banner: BannerView?

    init() {
        super.init(logTag: "Video")
        heightAnchor.constraint(equalToConstant: Self.slotHeight).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadAd() {
        super.loadAd()
        removeBanner()

        let banner = BannerView(frame: CGRect(origin: .zero, size: Self.adSize),
                                configID: Self.configID,
                                adSize: Self.adSize)
        banner.adFormat = .video
        banner.delegate = self
        banner.videoPlaybackDelegate = self

        let parameters = banner.videoParameters
        parameters.mimes = ["video/mp4", "video/quicktime", "video/x-m4v", "video/3gpp"]
        parameters.protocols = [.VAST_2_0, .VAST_3_0, .VAST_4_0]
        // Muted autoplay: the in-feed convention, and the only playback method whose OMSDK volume-change
        // events are worth watching as the ad scrolls.
        parameters.playbackMethod = [.AutoPlaySoundOff]
        parameters.placement = .InBanner
        // plcmnt is the OpenRTB 2.6 replacement for placement; both are sent so servers on either spec
        // version can target the slot.
        parameters.plcmnt = .NoContent
        parameters.api = [.OMID_1]
        parameters.startDelay = .PreRoll
        parameters.adSize = Self.adSize

        // One-shot load. Auto-refresh would tear down the creative — and with it the OMSDK session and any
        // in-flight video — at an arbitrary moment mid-scroll, which makes tracking unreadable.
        //banner.stopRefresh()

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

    // MARK: - BannerViewVideoPlaybackDelegate

    func videoPlaybackDidPause(_ banner: BannerView) {
        report("videoPlaybackDidPause")
    }

    func videoPlaybackDidResume(_ banner: BannerView) {
        report("videoPlaybackDidResume")
    }

    func videoPlaybackWasMuted(_ banner: BannerView) {
        report("videoPlaybackWasMuted")
    }

    func videoPlaybackWasUnmuted(_ banner: BannerView) {
        report("videoPlaybackWasUnmuted")
    }

    func videoPlaybackDidComplete(_ banner: BannerView) {
        report("videoPlaybackDidComplete")
    }

    // MARK: - Private

    private func removeBanner() {
        banner?.stopRefresh()
        banner?.removeFromSuperview()
        banner = nil
    }

    private func formatted(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }
}
