import UIKit

/**
 Life360's custom Prebid renderer

 Ideally we want one single Life360Renderer that both Life360AdsSDK and PrebidMobile can use.
 However since SPM doesn't allow overlapping source targets or conditional dependencies,
 we are forced to have two separate implementations in Life360Renderer and Life360RendererInternal.
 One internal to Life360AdsSDK, and another external that depends on PrebidMobile.

 Keep this type stateless. `PrebidMobilePluginRegister` stores renderers by name, so one instance
 serves every ad unit in the process, including ones loading concurrently. Per-load state belongs on
 the `DisplayView`, which is per-slot.
 */
public class Life360RendererInternal: NSObject, PrebidMobilePluginRenderer {

    // Note: Keeping the name "NativoRenderer" for backward compatibility with the Prebid Server Nativo module
    public static let NAME = "NativoRenderer"
    public static let VERSION = "1.0.0"
    public let name = Life360RendererInternal.NAME
    public let version = Life360RendererInternal.VERSION
    public var data: [String: Any]?

    public func createBannerView(
        with frame: CGRect,
        bid: Bid,
        adConfiguration: AdUnitConfig,
        loadingDelegate: DisplayViewLoadingDelegate,
        interactionDelegate: DisplayViewInteractionDelegate
    ) -> PrebidMobileDisplayViewProtocol? {

        let displayView = DisplayView(
            frame: frame,
            bid: bid,
            adConfiguration: adConfiguration
        )

        displayView.interactionDelegate = interactionDelegate
        displayView.loadingDelegate = loadingDelegate

        return displayView
    }
    
    public func createInterstitialController(
        bid: Bid,
        adConfiguration: AdUnitConfig,
        loadingDelegate: InterstitialControllerLoadingDelegate,
        interactionDelegate: InterstitialControllerInteractionDelegate
    ) -> PrebidMobileInterstitialControllerProtocol? {
        let interstitialController = InterstitialController(
            bid: bid,
            adConfiguration: adConfiguration
        )
        
        interstitialController.loadingDelegate = loadingDelegate
        interstitialController.interactionDelegate = interactionDelegate
        
        return interstitialController
    }
    
    public func didInjectView(_ view: UIView, into bannerView: UIView) {
        // Cast to DisplayView to extract the bid
        guard let prebidDisplayView = view as? DisplayView else {
            Log.debug("displayView is not of type DisplayView", filename: #file, line: #line, function: #function)
            return
        }
        
        let bid = prebidDisplayView.bid
        if bid.usesLife360Rendering {
            renderLife360Ad(prebidDisplayView, into: bannerView, with: bid)
        }
    }

    private func renderLife360Ad(_ displayView: DisplayView, into bannerView: UIView, with bid: Bid) {
        DispatchQueue.main.async {
            let result = Life360AdLayout.applyLife360Expansion(
                displayView: displayView,
                in: bannerView,
                minimumHeight: bid.size.height
            )
            if case .failure(.missingCreativeSubview) = result {
                Log.error(
                    "Life360 expansion skipped: DisplayView has no creative subview yet, so the ad will "
                        + "stay at the raw bid size. The view was deployed before its creative loaded.",
                    filename: #file,
                    line: #line,
                    function: #function
                )
            }
            self.setModalBackground(bid: bid, displayView: displayView)
        }
    }

    // MARK: - Private functions

    private func setModalBackground(bid: Bid, displayView: DisplayView) {
        if bid.life360AdType == .story
            || bid.life360AdType == .ctpVideo
            || bid.life360AdType == .stpVideo {
            displayView.interstitialDisplayProperties.modalBackgroundColor = .black
        }
    }
}



