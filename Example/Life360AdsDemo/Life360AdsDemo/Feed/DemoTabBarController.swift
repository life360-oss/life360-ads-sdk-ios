//
//  DemoTabBarController.swift
//  Life360AdsDemoiOS
//

import UIKit

/// The app's root: one tab per ad type.
///
/// Each tab keeps its view controller — and so its ad — alive after the first visit, so switching tabs and
/// coming back doesn't re-run the auction. Only one auction per ad type per launch makes it possible to tell
/// a repeat impression from a repeat request.
final class DemoTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let banner = AdFeedViewController(title: "Banner",
                                         tabImageName: "rectangle",
                                         adSlot: BannerAdSlotView())
        let native = AdFeedViewController(title: "Native",
                                         tabImageName: "text.below.photo",
                                         adSlot: NativeAdSlotView())
        let life360Video = AdFeedViewController(title: "L360 Video",
                                                 tabImageName: "play.rectangle.on.rectangle",
                                                 adSlot: Life360VideoAdSlotView())
        
        // Full ORTB Video support planned for upcoming release
        //        let video = AdFeedViewController(title: "Video",
        //                                        tabImageName: "play.rectangle",
        //                                        adSlot: VideoAdSlotView())

        viewControllers = [banner, life360Video, native].map { feed in
            let navigation = UINavigationController(rootViewController: feed)
            navigation.navigationBar.prefersLargeTitles = false
            Self.style(navigation.navigationBar)
            return navigation
        }
    }

    /// A flat, opaque bar with a bold title and the app's accent colour for buttons.
    ///
    /// Opaque rather than the system default translucent bar: the feed scrolls its content underneath the
    /// bar (see `AdFeedViewController.sizeSpacers`), so a translucent bar would let the ad show through as it
    /// scrolls past — distracting, and not what "the nav bar" should be showing.
    private static func style(_ navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = UIColor(named: "AccentColor")
    }
}
