//
//  AdFeedViewController.swift
//  Life360AdsDemoiOS
//

import UIKit

/// A scrolling page holding a single ad slot, centred on open. One instance per tab, differing only in
/// which slot it builds.
///
/// The page is otherwise empty: the ad sits between two blank spacers, each a viewport tall, so it starts
/// in the middle of the screen and can be scrolled completely off the top or completely off the bottom.
/// Those two exits are the transitions Open Measurement and impression tracking are being observed for.
///
/// Deliberately a scroll view over a stack view rather than a table or collection view: cell reuse would
/// recycle the ad's container while it is off screen, and rebuilding the ad on the way back would restart
/// the OMSDK session and re-fire the impression trackers every time it scrolled past. Nothing here is
/// recycled, so an ad's viewability state changes with scroll position and nothing else.
final class AdFeedViewController: UIViewController, UIScrollViewDelegate {

    /// Empty scroll room added above and below the ad slot, on top of one screen height on each side. The
    /// screen height is what lets the ad leave the screen entirely; this margin just means it clears the edge
    /// with room to spare instead of stopping flush against it.
    private static let scrollMarginBeyondScreen: CGFloat = 80

    private let adSlot: AdSlotView
    private let scrollView = UIScrollView()
    private let topSpacer = UIView()
    private let bottomSpacer = UIView()

    private var topSpacerHeight: NSLayoutConstraint!
    private var bottomSpacerHeight: NSLayoutConstraint!

    /// Ad height the current scroll position was centred against, so a slot that resizes after its
    /// creative arrives can be re-centred without re-centring on every layout pass.
    private var centredAdHeight: CGFloat = 0

    /// Set on the first drag. Re-centring after that would yank the page out from under the reader.
    private var userHasScrolled = false

    /// Set once the slot has been laid out at its real width, since an ad unit built at zero width requests
    /// against the wrong viewport.
    private var hasRequestedAd = false

    init(title: String, tabImageName: String, adSlot: AdSlotView) {
        self.adSlot = adSlot
        super.init(nibName: nil, bundle: nil)
        self.title = title
        tabBarItem = UITabBarItem(title: title,
                                  image: UIImage(systemName: tabImageName),
                                  selectedImage: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildPage()

        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadTapped)
        )
        reload.accessibilityLabel = "Reload ad"
        navigationItem.rightBarButtonItem = reload
    }

    // MARK: - Actions

    @objc private func reloadTapped() {
        adSlot.loadAd()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let visibleHeight = self.visibleHeight
        guard visibleHeight > 0, view.bounds.width > 0 else { return }

        sizeSpacers()

        if !userHasScrolled, abs(adSlot.bounds.height - centredAdHeight) > 0.5 {
            // Spacer changes have to land before the slot's position can be measured.
            view.layoutIfNeeded()
            centredAdHeight = adSlot.bounds.height
            centreAdSlot(in: visibleHeight)
        }

        guard !hasRequestedAd else { return }
        hasRequestedAd = true
        adSlot.loadAd()
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userHasScrolled = true
    }

    // MARK: - Private

    /// Height of the region between the nav and tab bars — what the ad is centred in, so it looks centred
    /// rather than sitting behind a bar.
    private var visibleHeight: CGFloat {
        let inset = scrollView.adjustedContentInset
        return scrollView.bounds.height - inset.top - inset.bottom
    }

    private func buildPage() {
        let stack = UIStackView(arrangedSubviews: [topSpacer, adSlot, bottomSpacer])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        topSpacerHeight = topSpacer.heightAnchor.constraint(equalToConstant: 0)
        bottomSpacerHeight = bottomSpacer.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            topSpacerHeight,
            bottomSpacerHeight,

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    /// Grows both spacers to a full viewport plus margin, which is what buys the ad room to leave the screen
    /// at either end.
    ///
    /// Measured against the scroll view's whole frame, not the inset region between the bars: the scroll
    /// view runs underneath the translucent nav and tab bars, so an ad that only clears the inset region is
    /// still on screen — dimmed under a bar, and still geometrically viewable as far as OMSDK is concerned.
    private func sizeSpacers() {
        let target = scrollView.bounds.height + Self.scrollMarginBeyondScreen
        guard abs(topSpacerHeight.constant - target) > 0.5 else { return }
        topSpacerHeight.constant = target
        bottomSpacerHeight.constant = target
    }

    private func centreAdSlot(in visibleHeight: CGFloat) {
        // A subview's frame in the scroll view's own coordinate space is already content coordinates.
        let slotInContent = scrollView.convert(adSlot.bounds, from: adSlot)
        let offsetY = slotInContent.midY - visibleHeight / 2 - scrollView.adjustedContentInset.top
        scrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
    }
}
