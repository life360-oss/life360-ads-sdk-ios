import UIKit
import WebKit

/**
 Nativo's custom Prebid renderer
 
 Ideally we want one single NativoPrebidRenderer that both NativoPrebidSDK and PrebidMobile can use.
 However since SPM doesn't allow overlapping source targets or conditional dependencies,
 we are forced to have two separate implementations in NativoPrebidRenderer and NativoPrebidRendererInternal.
 One internal to NativoPrebidSDK, and another external that depends on PrebidMobile.
 */
public class NativoPrebidRendererInternal: NSObject, PrebidMobilePluginRenderer, DisplayViewLoadingDelegate {

    public static let NAME = "NativoRenderer"
    public static let VERSION = "1.0.0"
    public let name = NativoPrebidRendererInternal.NAME
    public let version = NativoPrebidRendererInternal.VERSION
    public var data: [String: Any]?
    var bannerLoadingDelegate: DisplayViewLoadingDelegate?
    
    public func createBannerView(
        with frame: CGRect,
        bid: Bid,
        adConfiguration: AdUnitConfig,
        loadingDelegate: DisplayViewLoadingDelegate,
        interactionDelegate: DisplayViewInteractionDelegate
    ) -> (UIView & PrebidMobileDisplayViewProtocol)? {
        
        let displayView = DisplayView(
            frame: frame,
            bid: bid,
            adConfiguration: adConfiguration
        )
        
        self.bannerLoadingDelegate = loadingDelegate
        displayView.interactionDelegate = interactionDelegate
        displayView.loadingDelegate = self
        
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
        if (shouldRenderForBid(from: bid)) {
            renderNativoAd(prebidDisplayView, into: bannerView, with: bid)
        }
    }
    
    // Differenciate between Nativo ad rendering or a standard banner ad
    private func shouldRenderForBid(from bid: Bid) -> Bool {
        if let adType = bid.nativoAdType {
            // Only avoid Nativo rendering for standard display;
            // render for all other Nativo types
            return adType != .standardDisplay
        } else {
            // fallback
            let adm = bid.adm ?? ""
            let isNativoRendering = adm.range(of: "load.js", options: .caseInsensitive) != nil
            return isNativoRendering
        }
    }
    
    private func renderNativoAd(_ displayView: DisplayView, into bannerView: UIView, with bid: Bid) {
        DispatchQueue.main.async {
            self.expandFullWidth(bannerView)
            self.expandFullHeight(bannerView)
            self.expandChildren(displayView, to: bannerView, withMinimum:bid.size.height)
            self.setModalBackground(bid: bid, displayView: displayView)
        }
    }
    
    
    // MARK: - DisplayViewLoadingDelegate
    
    public func displayViewDidLoadAd(_ displayView: UIView) {
        self.bannerLoadingDelegate?.displayViewDidLoadAd(displayView)
    }
    
    public func displayView(_ displayView: UIView, didFailWithError error: any Error) {
        self.bannerLoadingDelegate?.displayView(displayView, didFailWithError: error)
    }
    
    // MARK: - Private functions
    
    private func setModalBackground(bid: Bid, displayView: DisplayView) {
        if bid.nativoAdType == .story
            || bid.nativoAdType == .ctpVideo
            || bid.nativoAdType == .stpVideo {
            displayView.interstitialDisplayProperties.modalBackgroundColor = .black
        }
    }
    
    private func expandFullWidth(_ view: UIView) {
        if let parentView = view.superview {
            // Remove any constraints we don't need
            let constraints = parentView.constraints
            let widthConstraints = constraints.filter({ constraint in
                (constraint.firstItem as? UIView) === view && constraint.firstAttribute == .width
                || (constraint.secondItem as? UIView) === view && constraint.secondAttribute == .width
            })
            NSLayoutConstraint.deactivate(widthConstraints)
            
            view.widthAnchor.constraint(equalTo: parentView.widthAnchor).isActive = true
        }
    }
    
    private func expandFullHeight(_ view: UIView) {
        if let parentView = view.superview {
            // Remove any constraints we don't need
            let constraints = parentView.constraints
            let heightConstraints = constraints.filter({ constraint in
                (constraint.firstItem as? UIView) === view && constraint.firstAttribute == .height
                || (constraint.secondItem as? UIView) === view && constraint.secondAttribute == .height
            })
            NSLayoutConstraint.deactivate(heightConstraints)
            
            view.heightAnchor.constraint(equalTo: parentView.heightAnchor).isActive = true
        }
    }
    
    private func expandChildren(_ view: UIView, to parentView: UIView, withMinimum height: CGFloat) {
        let minHeight = view.heightAnchor.constraint(greaterThanOrEqualToConstant: height)
        let width = view.widthAnchor.constraint(equalTo: parentView.widthAnchor)
        let height = view.heightAnchor.constraint(equalTo: parentView.heightAnchor)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            width,
            height,
            minHeight
        ])
        
        guard let childView = view.subviews.first else {
            let error = NSError(
                domain: "NativoPrebidRenderer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Nativo renderer expected a subview on DisplayView, but none was found."]
            )
            print("\(error)")
            return
        }
        
        walkFirstChildChain(from: childView, stopAtType: WKWebView.self) { subview in
            expandFullWidth(subview)
            expandFullHeight(subview)
        }
    }
    
    private func walkFirstChildChain<T: UIView>(
        from view: UIView,
        stopAtType: T.Type,
        withAction: (UIView) -> Void
    ) {
        var current: UIView? = view
        while let v = current {
            withAction(v)
            if v.subviews.first is T { break }
            current = v.subviews.first
        }
    }
}



