
import Foundation
import UIKit

/// Nativo-specific `BannerView` callbacks
@objc public protocol NativoBannerViewDelegate: BannerViewDelegate {

    /// Notifies the delegate that a Nativo ad won and will be rendered with the NativoRenderer.
    /// `bannerView(_:didReceiveAdWithAdSize:)` will not be called for the same load.
    /// - Parameters:
    ///   - bannerView: The BannerView instance sending the message.
    ///   - adSize: The size of the loaded Nativo ad.
    func bannerView(_ bannerView: BannerView, didReceiveNativoAdWithSize adSize: CGSize)
}
