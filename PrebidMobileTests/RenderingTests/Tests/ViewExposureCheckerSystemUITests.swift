//
// Copyright 2018-2026 Prebid.org, Inc.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
    

import Foundation
import XCTest
@testable @_spi(PBMInternal) import Life360AdsSDK

class PBMViewExposureCheckerSystemUITests: XCTestCase {
    
    var window: UIWindow!
    var adView: UIView!
    
    override func setUp() {
        super.setUp()
        
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.makeKeyAndVisible()
        
        adView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 250))
        adView.backgroundColor = .red
    }
    
    override func tearDown() {
        window.isHidden = true
        window = nil
        adView = nil
        
        super.tearDown()
    }
        
    func testExposureMethod() {
        let viewController = UIViewController()
        window.rootViewController = viewController
        viewController.view.addSubview(adView)
        
        viewController.view.layoutIfNeeded()
        
        let exposure = PBMViewExposureChecker.exposure(of: adView)
        
        XCTAssertGreaterThan(exposure.exposureFactor, 0.95)
    }
    
    func testExposureProperty() {
        let viewController = UIViewController()
        window.rootViewController = viewController
        viewController.view.addSubview(adView)
        
        viewController.view.layoutIfNeeded()
        
        let checker = PBMViewExposureChecker(view: adView)
        let exposure = checker.exposure
        
        XCTAssertGreaterThan(exposure.exposureFactor, 0.95)
    }
    
    func testBothAPIsReturnSameResult() {
        let viewController = UIViewController()
        window.rootViewController = viewController
        viewController.view.addSubview(adView)
        
        viewController.view.layoutIfNeeded()
        
        let classMethodExposure = PBMViewExposureChecker.exposure(of: adView)
        let instanceChecker = PBMViewExposureChecker(view: adView)
        let instanceExposure = instanceChecker.exposure
        
        XCTAssertEqual(classMethodExposure.exposureFactor, instanceExposure.exposureFactor, accuracy: 0.001)
    }
        
    func testIgnoresNavigationBar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.navigationBar.isTranslucent = true
        
        window.rootViewController = navigationController
        
        viewController.view.addSubview(adView)
        
        // Position ad view where it might overlap with navigation bar
        adView.frame = CGRect(x: 0, y: 50, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testIgnoresOpaqueNavigationBar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.navigationBar.isTranslucent = false
        navigationController.navigationBar.barTintColor = .blue
        
        window.rootViewController = navigationController
        viewController.view.addSubview(adView)
        
        adView.frame = CGRect(x: 0, y: 50, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testIgnoresTabBar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [viewController]
        tabBarController.tabBar.isTranslucent = true
        
        window.rootViewController = tabBarController
        
        viewController.view.addSubview(adView)
        
        // Position ad view where it might overlap with tab bar at bottom
        adView.frame = CGRect(x: 0, y: 400, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testIgnoresOpaqueTabBar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [viewController]
        tabBarController.tabBar.isTranslucent = false
        tabBarController.tabBar.barTintColor = .blue
        
        window.rootViewController = tabBarController
        viewController.view.addSubview(adView)
        
        // Position ad view where it might overlap with tab bar at bottom
        adView.frame = CGRect(x: 0, y: 400, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testIgnoresBothNavigationAndTabBars() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.navigationBar.isTranslucent = true
        
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [navigationController]
        tabBarController.tabBar.isTranslucent = true
        
        window.rootViewController = tabBarController
        
        viewController.view.addSubview(adView)
        
        // Position ad to potentially overlap both bars
        adView.frame = CGRect(x: 0, y: 200, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
        
    func testIgnoresToolbar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.setToolbarHidden(false, animated: false)
        navigationController.toolbar.isTranslucent = true
        
        window.rootViewController = navigationController
        
        viewController.view.addSubview(adView)
        
        // Position ad near bottom where toolbar appears
        adView.frame = CGRect(x: 0, y: 400, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testIgnoresOpaqueToolbar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.setToolbarHidden(false, animated: false)
        navigationController.toolbar.isTranslucent = false
        navigationController.toolbar.barTintColor = .blue
        
        window.rootViewController = navigationController
        viewController.view.addSubview(adView)
        
        // Position ad near bottom where toolbar appears
        adView.frame = CGRect(x: 0, y: 400, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
        
    func testIgnoresSearchBar() {
        // UISearchBar can also overlap content when used in navigation items
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let navigationController = UINavigationController(rootViewController: viewController)
        
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.isTranslucent = true
        viewController.navigationItem.searchController = searchController
        viewController.navigationItem.hidesSearchBarWhenScrolling = false
        
        window.rootViewController = navigationController
        viewController.view.addSubview(adView)
        
        adView.frame = CGRect(x: 0, y: 0, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
        
    func testIgnoresHiddenViews() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        window.rootViewController = viewController
        viewController.view.addSubview(adView)
        
        let hiddenView = UIView(frame: adView.frame)
        hiddenView.backgroundColor = .black
        hiddenView.isHidden = true
        viewController.view.addSubview(hiddenView)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testAdViewFullyBelowNavigationBar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let navigationController = UINavigationController(rootViewController: viewController)
        
        window.rootViewController = navigationController
        viewController.view.addSubview(adView)
        
        adView.frame = CGRect(x: 0, y: 200, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testAdViewFullyAboveTabBar() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [viewController]
        
        window.rootViewController = tabBarController
        viewController.view.addSubview(adView)
        
        // Position ad above tab bar
        adView.frame = CGRect(x: 0, y: 0, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    func testEmptyViewHierarchy() {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        
        window.rootViewController = viewController
        viewController.view.addSubview(adView)
        
        adView.frame = CGRect(x: 0, y: 0, width: 320, height: 250)
        
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        
        let exposure = calculateExposure(for: adView)
        
        XCTAssertGreaterThan(exposure, 0.95)
    }
    
    // MARK: - Helper Methods
    
    private func calculateExposure(for view: UIView) -> CGFloat {
        let exposure = PBMViewExposureChecker.exposure(of: view)
        return CGFloat(exposure.exposureFactor)
    }
    
    private func calculateExposureWithChecker(for view: UIView) -> CGFloat {
        let checker = PBMViewExposureChecker(view: view)
        return CGFloat(checker.exposure.exposureFactor)
    }
}

/// Verifies `Life360ViewExposureChecker.friendlyObstructionViews` — every overlapping view that itself
/// paints nothing over the ad, which the OM path registers as OMID friendly obstructions so transparent
/// overlays stop eroding measured viewability. OMID judges each overlapping view on its own, so the list
/// is per-view rather than per-subtree: a non-painting container is registered even when something
/// deeper inside it draws, and that drawing descendant stays an occluder.
class Life360FriendlyObstructionTests: XCTestCase {

    var window: UIWindow!
    var viewController: UIViewController!
    var adView: UIView!

    override func setUp() {
        super.setUp()

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.makeKeyAndVisible()

        viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window.rootViewController = viewController

        adView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 250))
        adView.backgroundColor = .red
        viewController.view.addSubview(adView)
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        viewController = nil
        adView = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func friendlyObstructions() -> [UIView] {
        viewController.view.layoutIfNeeded()
        window.layoutIfNeeded()
        let checker = Life360ViewExposureChecker(view: adView, onExposureChange: nil)
        return checker.friendlyObstructionViews()
    }

    private func addOverlay(_ view: UIView, frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) {
        view.frame = frame
        viewController.view.addSubview(view) // added after adView -> drawn on top
    }

    private func assertFriendly(_ view: UIView, _ friendly: [UIView], file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(friendly.contains { $0 === view }, "expected view to be a friendly obstruction", file: file, line: line)
    }

    private func assertNotFriendly(_ view: UIView, _ friendly: [UIView], file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(friendly.contains { $0 === view }, "expected view NOT to be a friendly obstruction", file: file, line: line)
    }

    // MARK: - Tests

    func testTransparentOverlayIsFriendly() {
        let overlay = UIView()
        overlay.backgroundColor = .clear
        addOverlay(overlay)

        assertFriendly(overlay, friendlyObstructions())
    }

    func testOverlayWithNoBackgroundColorIsFriendly() {
        // A gesture/tap-catching overlay with no background at all still overlaps but draws nothing.
        let overlay = UIView()
        overlay.backgroundColor = nil
        addOverlay(overlay)

        assertFriendly(overlay, friendlyObstructions())
    }

    func testOpaqueBackgroundOverlayIsNotFriendly() {
        let overlay = UIView()
        overlay.backgroundColor = .blue
        addOverlay(overlay)

        assertNotFriendly(overlay, friendlyObstructions())
    }

    func testLabelWithTextIsNotFriendly() {
        let label = UILabel()
        label.text = "Sponsored"
        label.textColor = .black
        addOverlay(label)

        assertNotFriendly(label, friendlyObstructions())
    }

    func testImageViewWithImageIsNotFriendly() {
        let imageView = UIImageView()
        imageView.image = UIImage()
        addOverlay(imageView)

        assertNotFriendly(imageView, friendlyObstructions())
    }

    func testHiddenOverlayIsNotFriendly() {
        let overlay = UIView()
        overlay.backgroundColor = .clear
        overlay.isHidden = true
        addOverlay(overlay)

        assertNotFriendly(overlay, friendlyObstructions())
    }

    func testNonOverlappingOverlayIsNotFriendly() {
        let overlay = UIView()
        overlay.backgroundColor = .clear
        addOverlay(overlay, frame: CGRect(x: 0, y: 400, width: 100, height: 100)) // below the ad

        assertNotFriendly(overlay, friendlyObstructions())
    }

    func testViewBelowAdInZOrderIsNotConsidered() {
        // Inserted beneath the ad view; OMID only counts views drawn on top, so it must not appear.
        let underlay = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        underlay.backgroundColor = .clear
        viewController.view.insertSubview(underlay, belowSubview: adView)

        assertNotFriendly(underlay, friendlyObstructions())
    }

    func testTransparentContainerWithOpaqueChildIsNotFriendly() {
        // The child's layer is a sublayer of the container's, so an opaque background one level down
        // counts as the container painting: neither it nor the child may be registered.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        container.backgroundColor = .clear
        let opaqueChild = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        opaqueChild.backgroundColor = .green
        container.addSubview(opaqueChild)
        addOverlay(container, frame: container.frame)

        let friendly = friendlyObstructions()
        assertNotFriendly(container, friendly)
        assertNotFriendly(opaqueChild, friendly)
    }

    func testFullyTransparentContainerAndChildAreBothFriendly() {
        // Container and child both transparent -> each is registered on its own. Declaring the nested
        // child alongside its container is redundant for OMID but harmless, and it is what lets a
        // container be declared even when a deeper descendant draws.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        container.backgroundColor = .clear
        let transparentChild = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        transparentChild.backgroundColor = .clear
        container.addSubview(transparentChild)
        addOverlay(container, frame: container.frame)

        let friendly = friendlyObstructions()
        assertFriendly(container, friendly)
        assertFriendly(transparentChild, friendly)
    }

    /// The regression this collection logic exists for: on iOS 26 SwiftUI wraps an ad in containers that
    /// paint nothing themselves but hold a small drawing view two levels down. Judging the container by
    /// its own painting keeps it declared, so OMID charges only the drawing view's rect.
    func testNonPaintingContainerIsFriendlyWhenOnlyADeepDescendantDraws() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 250))
        container.backgroundColor = .clear
        let passthrough = UIView(frame: container.bounds)
        passthrough.backgroundColor = .clear
        let drawingDescendant = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        drawingDescendant.backgroundColor = .green
        passthrough.addSubview(drawingDescendant)
        container.addSubview(passthrough)
        addOverlay(container, frame: container.frame)

        let friendly = friendlyObstructions()
        assertFriendly(container, friendly)
        assertNotFriendly(drawingDescendant, friendly)
    }
}

/// Covers how `Life360ViewExposureChecker` behaves the moment an ad is loaded, before any scrolling:
/// which initializer the caller used must not change the measured exposure, and a checker with a handler
/// has to report once on its own.
class Life360ViewExposureCheckerInitialLoadTests: XCTestCase {

    var window: UIWindow!
    var viewController: UIViewController!
    var adView: UIView!

    override func setUp() {
        super.setUp()

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.makeKeyAndVisible()

        viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window.rootViewController = viewController

        adView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 250))
        adView.backgroundColor = .red
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        viewController = nil
        adView = nil
        super.tearDown()
    }

    /// PBMCreativeViewabilityTracker constructs the checker through the superclass initializer, so that
    /// path has to measure the same view as the handler based one.
    func testSuperclassInitializerMeasuresTheView() {
        viewController.view.addSubview(adView)
        viewController.view.layoutIfNeeded()

        let checker = Life360ViewExposureChecker(view: adView)

        XCTAssertGreaterThan(checker.exposure.exposureFactor, 0.95)
    }

    func testBothInitializersReportTheSameExposure() {
        viewController.view.addSubview(adView)
        viewController.view.layoutIfNeeded()

        let superclassInit = Life360ViewExposureChecker(view: adView)
        let handlerInit = Life360ViewExposureChecker(view: adView, onExposureChange: nil)

        XCTAssertEqual(superclassInit.exposure.exposureFactor,
                       handlerInit.exposure.exposureFactor,
                       accuracy: 0.001)
    }

    /// The initial report is what makes an ad that loads already on screen viewable without the user
    /// scrolling first.
    func testInitialExposureIsReportedWithoutScrolling() {
        let scrollView = UIScrollView(frame: window.bounds)
        viewController.view.addSubview(scrollView)
        scrollView.addSubview(adView)
        viewController.view.layoutIfNeeded()

        let reported = expectation(description: "initial exposure reported")
        var exposureFactor: Float?
        var reportedError: Error?

        let checker = Life360ViewExposureChecker(view: adView) { exposure, error in
            exposureFactor = exposure.exposureFactor
            reportedError = error
            reported.fulfill()
        }

        withExtendedLifetime(checker) {
            waitForExpectations(timeout: 2)
        }

        XCTAssertNil(reportedError)
        XCTAssertEqual(exposureFactor ?? 0, 1, accuracy: 0.05)
    }

    /// Without a scrollable ancestor there is nothing to observe, so the checker reports zero plus an
    /// error and leaves the caller to fall back to polling.
    func testMissingScrollAncestorReportsZeroWithError() {
        viewController.view.addSubview(adView)
        viewController.view.layoutIfNeeded()

        let reported = expectation(description: "failure reported")
        var exposureFactor: Float?
        var reportedError: Error?

        let checker = Life360ViewExposureChecker(view: adView) { exposure, error in
            exposureFactor = exposure.exposureFactor
            reportedError = error
            reported.fulfill()
        }

        withExtendedLifetime(checker) {
            waitForExpectations(timeout: 2)
        }

        XCTAssertNotNil(reportedError)
        XCTAssertEqual(exposureFactor, 0)
    }
}
