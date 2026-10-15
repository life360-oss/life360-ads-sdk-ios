/*   Copyright 2018-2021 Prebid.org, Inc.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import UIKit
import WebKit

/// Modified from `ViewExposureChecker` to support scroll based tracking instead of timer based polling.
/// Also fixes an issue where tracking would stop during user touch.
@objc(Life360ViewExposureChecker) @_spi(PBMInternal) public
class Life360ViewExposureChecker: ViewExposureChecker {

    public typealias ExposureChangeHandler = (ViewExposure, Error?) -> Void

    private enum OcclusionType {
        case none        // hidden, or does not overlap the ad
        case transparent // overlaps the ad but paints nothing over it
        case opaque      // paints opaque content over the ad somewhere in the subtree
    }

    // Treat nearly-transparent as transparent.
    private static let alphaEpsilon: CGFloat = 0.01

    private weak var testedView: UIView?
    private var clippedRect: CGRect = .zero
    private var obstructions: [CGRect] = []
    private var colorAlphaCache: [UIColor: CGFloat] = [:]

    private let onExposureChange: ExposureChangeHandler?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var attachPollTimer: Timer?
    private var trackScroll: (() -> Void)?

    @objc(initWithView:)
    public override convenience init(view: UIView) {
        self.init(view: view, onExposureChange: nil)
    }

    @objc(initWithView:onExposureChange:)
    public init(view: UIView, onExposureChange: ExposureChangeHandler?) {
        self.testedView = view
        self.onExposureChange = onExposureChange
        super.init(view: view)

        // Observation exists only to push updates into the handler, so pollers that pass none are spared
        // the KVO registration and the attach timer.
        if onExposureChange != nil {
            beginAttachPollingIfNeededAndSetupObservation()
        }
    }

    deinit {
        contentOffsetObservation?.invalidate()
        attachPollTimer?.invalidate()
    }

    // MARK: - Observation setup

    private func beginAttachPollingIfNeededAndSetupObservation() {
        if isOnForeground() {
            setupScrollObserving()
            return
        }

        Log.debug("Viewability: \(testedViewClassName) is not in a foreground window yet, polling until it attaches")
        attachPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, self.isOnForeground() else { return }
            timer.invalidate()
            self.attachPollTimer = nil
            self.setupScrollObserving()
        }
    }

    private func setupScrollObserving() {
        guard contentOffsetObservation == nil else { return }

        guard let scrollView = testedView.flatMap(parentContainer(for:)) as? UIScrollView,
              isActiveScrollView(scrollView) else {
            Log.debug("Viewability: no scrollable ancestor of \(testedViewClassName), reporting zero exposure so the caller can fall back to polling")
            notifyExposureChange(Factory.ViewExposureType.zeroExposure(),
                                 error: PBMError.error(description: "Failed to find UIScrollView parent."))
            return
        }

        Log.debug("Viewability: tracking exposure of \(testedViewClassName) against scroll view \(type(of: scrollView))")

        trackScroll = Life360Utils.throttle(interval: 0.15) { [weak self] in
            guard let self else { return }
            self.notifyExposureChange(self.calculateExposure(), error: nil)
        }

        contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.trackScroll?()
        }

        // Perform initial check that doesn't rely on scrolling.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notifyExposureChange(self.calculateExposure(), error: nil)
        }
    }

    // MARK: - Exposure delivery

    private func notifyExposureChange(_ exposure: ViewExposure, error: Error?) {
        Log.debug(String(format: "Viewability: %@ exposure %.1f%%, visible %@, %lu occlusion(s)",
                         testedViewClassName,
                         exposure.exposedPercentage,
                         NSCoder.string(for: exposure.visibleRectangle),
                         exposure.occlusionRectangles?.count ?? 0))
        onExposureChange?(exposure, error)
    }

    private var testedViewClassName: String {
        testedView.map { String(describing: type(of: $0)) } ?? "nil"
    }

    // MARK: - Exposure calculation

    public override var exposure: ViewExposure {
        calculateExposure()
    }

    private func calculateExposure() -> ViewExposure {
        guard let view = testedView else { return Factory.ViewExposureType.zeroExposure() }

        clippedRect = view.bounds
        obstructions.removeAll()

#if DEBUG
        if (Prebid.shared.value(forKey: "forcedIsViewable") as? Bool) == true {
            return Factory.createViewExposure(exposureFactor: 1, visibleRectangle: view.bounds, occlusionRectangles: nil)
        }
#endif

        guard !view.isHidden, let parent = view.superview, isOnForeground() else {
            return Factory.ViewExposureType.zeroExposure()
        }

        guard visitParent(parent, fromChild: view), collapseBoundingBox() else {
            return Factory.ViewExposureType.zeroExposure()
        }

        let occlusionRects = buildObstructionRects()
        let fullArea = Float(view.bounds.width * view.bounds.height)
        let clipArea = Float(clippedRect.width * clippedRect.height)
        let obstructedArea = occlusionRects.reduce(Float(0)) { $0 + Float($1.width * $1.height) }

        return Factory.createViewExposure(
            exposureFactor: (clipArea - obstructedArea) / fullArea,
            visibleRectangle: clippedRect,
            occlusionRectangles: occlusionRects.isEmpty ? nil : occlusionRects.map { NSValue(cgRect: $0) }
        )
    }

    private func isOnForeground() -> Bool {
        guard let window = testedView?.window else { return false }
        guard UIApplication.shared.applicationState == .active else { return false }
        return window.windowScene?.activationState == .foregroundActive
    }

    private func isActiveScrollView(_ view: UIView) -> Bool {
        view is UIScrollView && view.isUserInteractionEnabled
    }

    private func parentContainer(for view: UIView) -> UIView {
        var container = view
        while let superview = container.superview, !(superview is UIWindow), !isActiveScrollView(container) {
            container = superview
        }
        return container
    }

    // MARK: - Opacity

    private func isEffectivelyHidden(_ view: UIView) -> Bool {
        view.isHidden
            || view.alpha <= Self.alphaEpsilon
            || view.bounds.isEmpty
            || testedView?.window == nil
            || view.window == nil
    }

    private func alpha(of color: UIColor?) -> CGFloat {
        guard let color else { return 0 }
        if let cached = colorAlphaCache[color] {
            return cached
        }

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        if !color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            alpha = color.cgColor.alpha
        }
        colorAlphaCache[color] = alpha
        return alpha
    }

    /// Heuristic for whether `view` draws non-transparent content within `boundsRect`.
    /// `boundsRect` is in the view's own coordinate space, so sublayer frames can be compared directly.
    private func viewHasOpaqueVisualContent(_ view: UIView, in boundsRect: CGRect) -> Bool {
        let epsilon = Self.alphaEpsilon
        if view.alpha <= epsilon || CGFloat(view.layer.opacity) <= epsilon {
            return false
        }

        if alpha(of: view.backgroundColor) > epsilon {
            return true
        }
        if let layerBackground = view.layer.backgroundColor, layerBackground.alpha > epsilon {
            return true
        }

        switch view {
        case is UIVisualEffectView, is WKWebView:
            return true
        case let imageView as UIImageView where imageView.image != nil:
            return true
        case let label as UILabel where !(label.text ?? "").isEmpty && alpha(of: label.textColor) > epsilon:
            return true
        case let textView as UITextView where !textView.text.isEmpty && alpha(of: textView.textColor) > epsilon:
            return true
        case let button as UIButton:
            if button.currentImage != nil || button.currentBackgroundImage != nil {
                return true
            }
            if !(button.title(for: .normal) ?? "").isEmpty && alpha(of: button.titleColor(for: .normal)) > epsilon {
                return true
            }
        default:
            break
        }

        if view.layer.contents != nil {
            return true
        }
        for sublayer in view.layer.sublayers ?? [] {
            guard CGFloat(sublayer.opacity) > epsilon, sublayer.frame.intersects(boundsRect) else { continue }
            if let background = sublayer.backgroundColor, background.alpha > epsilon {
                return true
            }
            if sublayer.contents != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Obstruction traversal

    /// Returns `false` if exposure is zero.
    private func visitParent(_ parent: UIView, fromChild child: UIView) -> Bool {
        guard !parent.isHidden, let view = testedView else { return false }

        if parent.clipsToBounds || parent === view.window {
            clippedRect = clippedRect.intersection(view.convert(parent.bounds, from: parent))
            if clippedRect.isEmpty { return false }
        }

        if let grandparent = parent.superview, !visitParent(grandparent, fromChild: parent) {
            return false
        }

        var friendly: [UIView] = []
        for sibling in viewsAbove(child, in: parent) {
            collectObstructions(from: sibling, clip: clippedRect, obstructions: &obstructions, friendly: &friendly)
        }
        return true
    }

    private func viewsAbove(_ child: UIView, in parent: UIView) -> ArraySlice<UIView> {
        let siblings = parent.subviews
        guard let index = siblings.firstIndex(of: child) else { return [] }
        return siblings[(index + 1)...]
    }

    /// Single traversal shared by the exposure calculation and OMID friendly-obstruction detection: one
    /// opacity decision per view, reported through two channels. `obstructions` receives the intersecting
    /// rect of every view that paints opaque content over the ad. `friendly` receives every view that
    /// paints nothing over the ad — OMID would otherwise count those transparent overlays as occluders.
    /// Each visited view lands in exactly one channel.
    @discardableResult
    private func collectObstructions(from view: UIView,
                                     clip: CGRect,
                                     obstructions: inout [CGRect],
                                     friendly: inout [UIView]) -> OcclusionType {
        guard let tested = testedView, !isEffectivelyHidden(view) else { return .none }

        let intersection = clip.intersection(tested.convert(view.bounds, from: view))
        if intersection.isEmpty {
            return .none
        }

        let selfOccludes = viewHasOpaqueVisualContent(view, in: view.convert(intersection, from: tested))
        if selfOccludes {
            obstructions.append(intersection)
            if view.clipsToBounds {
                // A clipping opaque view hides its subtree from both measurements: its rect already
                // accounts for the occluded region, and any transparent descendant sits behind it.
                return .opaque
            }
        } else {
            // OMID evaluates every overlapping view on its own, so a view that paints nothing over the ad is
            // a friendly obstruction even when a descendant does paint — that descendant is reported through
            // `obstructions`. Declaring only fully-transparent subtrees left containers sized to the ad (e.g.
            // SwiftUI's `_UIInheritedView` wrappers) undeclared, and OMID then charged their entire rect.
            friendly.append(view)
        }

        let nextClip = view.clipsToBounds ? intersection : clip
        var subtreeOccludes = selfOccludes
        for subview in view.subviews {
            if collectObstructions(from: subview, clip: nextClip, obstructions: &obstructions, friendly: &friendly) == .opaque {
                subtreeOccludes = true
            }
        }
        return subtreeOccludes ? .opaque : .transparent
    }

    // MARK: - Friendly obstructions (OMID)

    /// OMID treats every overlapping visible view as an occluder, even when it paints nothing over the ad.
    /// These are the on-top views that are transparent over the ad, so callers can register them as OMID
    /// friendly obstructions and stop those overlays from eroding the measured viewable area.
    @objc public func friendlyObstructionViews() -> [UIView] {
        // No foreground gate: the only caller (OM session setup) is already foreground, and which
        // overlapping views are transparent is independent of app state.
        guard let tested = testedView, tested.superview != nil else { return [] }

        // OMID measures within the ad's own bounds, and only views drawn on top of the ad can occlude it,
        // so clip to the ad bounds and walk later siblings up the ancestor chain.
        var result: [UIView] = []
        var discardedObstructions: [CGRect] = []
        var child = tested
        while let parent = child.superview, !parent.isHidden {
            for sibling in viewsAbove(child, in: parent) {
                collectObstructions(from: sibling, clip: tested.bounds, obstructions: &discardedObstructions, friendly: &result)
            }
            child = parent
        }
        return result
    }

    // MARK: - Rect math

    /// Returns `true` if it resulted in a non-empty rect.
    private func collapseBoundingBox() -> Bool {
        let oldRect = clippedRect
        guard !oldRect.isEmpty else { return false }

        var fragments = [clippedRect]
        for obstruction in obstructions {
            fragments = fragments.flatMap { fragmentize($0, around: obstruction) }
            if fragments.isEmpty {
                clippedRect = .zero
                return false
            }
        }

        let result = fragments.dropFirst().reduce(fragments[0]) { $0.union($1) }
        if result == oldRect {
            return true
        }
        clippedRect = result

        obstructions = obstructions.compactMap { obstruction in
            guard obstruction.intersects(result) else { return nil }
            return result.contains(obstruction) ? obstruction : result.intersection(obstruction)
        }
        return true
    }

    /// Splits the obstructions into non-overlapping rects, largest first, so their areas can be summed.
    private func buildObstructionRects() -> [CGRect] {
        var remaining = obstructions
        var picked: [CGRect] = []

        while !remaining.isEmpty {
            remaining.sort { $0.width * $0.height > $1.width * $1.height }
            let largest = remaining.removeFirst()
            picked.append(largest)
            remaining = remaining.flatMap { fragmentize($0, around: largest) }
        }
        return picked
    }

    /// The parts of `rect` that lie outside `hole`.
    private func fragmentize(_ rect: CGRect, around hole: CGRect) -> [CGRect] {
        if !rect.intersects(hole) { return [rect] }
        if hole.contains(rect) { return [] }

        let trimmed = hole.intersection(rect)
        return [
            CGRect(x: rect.minX, y: rect.minY, width: trimmed.minX - rect.minX, height: rect.height),       // left
            CGRect(x: trimmed.minX, y: rect.minY, width: trimmed.width, height: trimmed.minY - rect.minY), // mid/top
            CGRect(x: trimmed.minX, y: trimmed.maxY, width: trimmed.width, height: rect.maxY - trimmed.maxY), // mid/bottom
            CGRect(x: trimmed.maxX, y: rect.minY, width: rect.maxX - trimmed.maxX, height: rect.height),   // right
        ].filter { !$0.isEmpty }
    }
}
