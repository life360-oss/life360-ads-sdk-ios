
import Foundation
import UIKit

/// Optional Life360-specific `BannerView` callbacks.
@objc public protocol Life360BannerViewDelegate: BannerViewDelegate {

    /// Notifies the delegate that a Life360 ad won and will be rendered with the Life360Renderer.
    /// If implemented, will call here instead of `bannerView(_:didReceiveAdWithAdSize:)`
    /// - Parameters:
    ///   - bannerView: The BannerView instance sending the message.
    ///   - adSize: The size of the loaded Life360 ad.
    func bannerView(_ bannerView: BannerView, didReceiveLife360AdWithSize adSize: CGSize)
}
