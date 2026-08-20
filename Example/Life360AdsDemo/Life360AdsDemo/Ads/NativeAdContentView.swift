//
//  NativeAdContentView.swift
//  Life360AdsDemoiOS
//

import UIKit
import Life360AdsSDK

/// The publisher-owned layout for a native ad.
///
/// Native demand returns assets, not a creative, so the app supplies the layout. Keeping it in its own
/// view means the slot around it only has to deal with the auction and with registering this view for
/// tracking — and it makes clear which subviews are handed to the SDK as clickable.
final class NativeAdContentView: UIView {

    private let iconImageView = UIImageView()
    private let sponsoredLabel = UILabel()
    private let titleLabel = UILabel()
    private let mainImageView = UIImageView()
    private let bodyLabel = UILabel()
    private let ctaButton = UIButton(type: .system)

    /// Height of the main image, adjusted to the asset's real aspect ratio once it loads so the slot
    /// doesn't letterbox or crop demand that isn't 16:9.
    private var mainImageHeight: NSLayoutConstraint!

    /// Views the SDK attaches its click handlers to. Reported separately from the tracking view because
    /// registering the whole card as clickable makes it impossible to scroll past without clicking.
    var clickableViews: [UIView] { [mainImageView, titleLabel, ctaButton] }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Populates the layout from the bid's native assets.
    func bind(_ ad: NativeAd) {
        titleLabel.text = ad.title
        bodyLabel.text = ad.text
        sponsoredLabel.text = ad.sponsoredBy.map { "Sponsored · \($0)" } ?? "Sponsored"
        ctaButton.setTitle(ad.callToAction ?? "Learn more", for: .normal)

        iconImageView.isHidden = ad.iconUrl == nil
        RemoteImageLoader.load(ad.iconUrl, into: iconImageView)

        mainImageView.isHidden = ad.imageUrl == nil
        mainImageHeight.isActive = ad.imageUrl != nil
        RemoteImageLoader.load(ad.imageUrl, into: mainImageView) { [weak self] in
            self?.matchMainImageAspectRatio()
        }
    }

    // MARK: - Private

    private func setUpSubviews() {
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 6
        iconImageView.backgroundColor = .tertiarySystemFill

        sponsoredLabel.font = .preferredFont(forTextStyle: .caption2)
        sponsoredLabel.textColor = .secondaryLabel

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 2

        mainImageView.contentMode = .scaleAspectFill
        mainImageView.clipsToBounds = true
        mainImageView.layer.cornerRadius = 8
        mainImageView.backgroundColor = .tertiarySystemFill

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 3

        ctaButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        ctaButton.contentHorizontalAlignment = .leading
        // Off, so the tap goes through the gesture recognizer the SDK installs — a UIButton action of our
        // own would open the landing page without firing the bid's click trackers.
        ctaButton.isUserInteractionEnabled = false

        let header = UIStackView(arrangedSubviews: [iconImageView, sponsoredLabel])
        header.axis = .horizontal
        header.spacing = 8
        header.alignment = .center

        let stack = UIStackView(arrangedSubviews: [header, titleLabel, mainImageView, bodyLabel, ctaButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        mainImageHeight = mainImageView.heightAnchor.constraint(equalTo: mainImageView.widthAnchor,
                                                               multiplier: 9.0 / 16.0)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
            mainImageHeight,
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func matchMainImageAspectRatio() {
        guard let image = mainImageView.image, image.size.width > 0 else { return }
        mainImageHeight.isActive = false
        mainImageHeight = mainImageView.heightAnchor.constraint(
            equalTo: mainImageView.widthAnchor,
            multiplier: image.size.height / image.size.width
        )
        mainImageHeight.isActive = true
    }
}
