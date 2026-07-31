import UIKit
import WebKit

/// Auto-layout work for the NativoRenderer
enum NativoAdLayout {

    enum LayoutError: Error, Equatable {
        /// The DisplayView had no creative subview, so the child chain could not be expanded. This
        /// means the caller deployed the view before its creative finished loading.
        case missingCreativeSubview
    }

    /// Expands the banner and the DisplayView's first-child chain so a Nativo creative fills the
    /// container instead of being letterboxed inside the bid-sized frame.
    ///
    /// - Parameter minimumHeight: the bid height, applied as a floor so the ad never collapses.
    @discardableResult
    static func applyNativoExpansion(
        displayView: UIView,
        in bannerView: UIView,
        minimumHeight: CGFloat
    ) -> Result<Void, LayoutError> {
        assert(Thread.isMainThread, assertionMessageMainThread)

        expandFullWidth(bannerView)
        expandFullHeight(bannerView)
        return expandChildren(displayView, to: bannerView, withMinimum: minimumHeight)
    }

    static func expandFullWidth(_ view: UIView) {
        expand(view, matching: .width, along: \.widthAnchor)
    }

    static func expandFullHeight(_ view: UIView) {
        expand(view, matching: .height, along: \.heightAnchor)
    }

    /// Replaces any existing constraint the parent holds for this view on `attribute` with a match-parent
    /// one. The existing constraint has to be deactivated first, or the two conflict at layout time.
    ///
    /// One implementation for both axes: as two copies, the replace-don't-stack rule has to be changed
    /// twice and the axes can silently diverge.
    private static func expand(
        _ view: UIView,
        matching attribute: NSLayoutConstraint.Attribute,
        along anchor: KeyPath<UIView, NSLayoutDimension>
    ) {
        assert(Thread.isMainThread, assertionMessageMainThread)

        guard let parentView = view.superview else { return }

        let existing = parentView.constraints.filter { constraint in
            (constraint.firstItem as? UIView) === view && constraint.firstAttribute == attribute
                || (constraint.secondItem as? UIView) === view && constraint.secondAttribute == attribute
        }
        NSLayoutConstraint.deactivate(existing)

        view[keyPath: anchor].constraint(equalTo: parentView[keyPath: anchor]).isActive = true
    }

    /// Pins the view to its parent, then expands every view down the first-child chain to the web
    /// view. The chain has to be walked because the creative sits several wrapper views deep and each
    /// wrapper would otherwise clip the one below it.
    ///
    /// The match-height constraint is `.defaultHigh` so `minimum` can win when the creative is taller.
    @discardableResult
    static func expandChildren(
        _ view: UIView,
        to parentView: UIView,
        withMinimum minimum: CGFloat
    ) -> Result<Void, LayoutError> {
        assert(Thread.isMainThread, assertionMessageMainThread)

        let minHeight = view.heightAnchor.constraint(greaterThanOrEqualToConstant: minimum)
        let width = view.widthAnchor.constraint(equalTo: parentView.widthAnchor)
        let height = view.heightAnchor.constraint(equalTo: parentView.heightAnchor)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([width, height, minHeight])

        guard let childView = view.subviews.first else {
            return .failure(.missingCreativeSubview)
        }

        walkFirstChildChain(from: childView, stopAtType: WKWebView.self) { subview in
            expandFullWidth(subview)
            expandFullHeight(subview)
        }

        return .success(())
    }

    /// Applies `action` down the first-child chain, stopping once the next child is a `T`.
    /// The web view itself is left alone — it sizes to its own content.
    static func walkFirstChildChain<T: UIView>(
        from view: UIView,
        stopAtType: T.Type,
        _ action: (UIView) -> Void
    ) {
        var current: UIView? = view
        while let candidate = current {
            action(candidate)
            if candidate.subviews.first is T { break }
            current = candidate.subviews.first
        }
    }
}

private let assertionMessageMainThread = "NativoAdLayout is Auto Layout work; expected the main thread"
