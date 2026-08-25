//
//  ViewHierarchyUtils.swift
//  Life360AdsDemoiOS
//

import UIKit
import WebKit

/// View-tree traversal the ad slots need but shouldn't own: finding a presenter for clickthrough modals
/// and reaching into a rendered creative's `WKWebView`. Both are the same recursive walk, and every ad
/// slot would otherwise reimplement it.
enum ViewHierarchy {

    /// Nearest view controller up the responder chain, for `bannerViewPresentationController()`.
    ///
    /// The responder chain rather than a stored reference: an ad slot lives inside a scroll view inside a
    /// tab, and whichever controller currently owns it is the one that can present a modal over it.
    static func presentingViewController(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder {
            if let viewController = next as? UIViewController { return viewController }
            responder = next.next
        }
        return nil
    }

    /// First subview of `type` in `root`'s subtree, depth first.
    static func firstSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(ofType: type, in: subview) { return match }
        }
        return nil
    }
}
