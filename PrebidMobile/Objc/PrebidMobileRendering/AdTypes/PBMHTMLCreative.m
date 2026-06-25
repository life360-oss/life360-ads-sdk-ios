/*   Copyright 2018-2021 Prebid.org, Inc.

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

//MRAID spec URLs:
//https://www.iab.com/wp-content/uploads/2015/08/IAB_MRAID_v2_FINAL.pdf
//https://www.iab.com/wp-content/uploads/2017/07/MRAID_3.0_FINAL.pdf

#import "PBMAbstractCreative+Protected.h"

#import "NSException+PBMExtensions.h"
#import "NSString+PBMExtensions.h"
#import "UIView+PBMExtensions.h"

#import "PBMConstants.h"
#import "PBMDownloadDataHelper.h"
#import "PBMFunctions+Private.h"
#import "PBMHTMLCreative.h"
#import "PBMHTMLFormatter.h"
#import "PBMMacros.h"
#import "PBMModalState.h"
#import "PBMMRAIDCommand.h"
#import "PBMMRAIDConstants.h"
#import "PBMVideoView.h"
#import "PBMWebView.h"
#import "PBMMRAIDController.h"
#import "Log+Extensions.h"

#import "SwiftImport.h"

#pragma mark - Private Extension

@interface PBMHTMLCreative() <PBMWebViewDelegate>

@property (nonatomic, strong) NSURL *baseURL;
@property (nonatomic, strong) PBMWebView *prebidWebView;
@property (nonatomic, strong) Prebid *sdkConfiguration;
@property (nonatomic, strong) PBMMRAIDController *MRAIDController;

@property (nonatomic, strong) PBMRewardedConfig *rewardedConfig;
@property (nonatomic, strong, nullable) PBMBackgroundAwareTimer *backgroundAwareTimer;

// Used to prevent race conditions where the impression fires before the OM Session has been started.
@property (nonatomic, assign) BOOL openMeasurementSessionHasStarted;
@property (nonatomic, assign) BOOL needsOpenMeasurementSync;
@property (nonatomic, assign) BOOL webviewFailedToLoad;

@end

#pragma mark - Implementation

@implementation PBMHTMLCreative

#pragma mark - Initialization

- (nonnull instancetype)initWithCreativeModel:(PBMCreativeModel *)creativeModel
                                  transaction:(id<PBMTransaction>)transaction {
    self = [self initWithCreativeModel:creativeModel
                           transaction:transaction
                               webView:nil
                      sdkConfiguration:Prebid.shared];
    
    return self;
}

- (nonnull instancetype)initWithCreativeModel:(PBMCreativeModel *)creativeModel
                                  transaction:(id<PBMTransaction>)transaction
                                      webView:(PBMWebView *)webView
                             sdkConfiguration:(Prebid *)sdkConfiguration {
    self = [super initWithCreativeModel:creativeModel transaction:transaction];
    if (self) {
        self.sdkConfiguration = sdkConfiguration;
        
        // TODO: set proper base URL for prebid
        //Set the baseURL. This will cause relative URLs in the creative to inherit the URL scheme used.
        self.baseURL = nil;
        
        if (webView) {
            self.prebidWebView = webView;
        }
        
        self.rewardedConfig = self.creativeModel.adConfiguration.rewardedConfig;
    }
    
    return self;
}

#pragma mark - PBMAbstractCreative

- (BOOL)isOpened {
    return self.clickthroughVisible || (self.MRAIDController && self.MRAIDController.mraidState != PBMMRAIDState.defaultState);
}

- (NSNumber *)displayInterval {
    return self.creativeModel.displayDurationInSeconds;
}

- (void)setupView {
    [super setupView];
    
    NSString *html = self.creativeModel.html;
    if (!html) {
        [self onResolutionFailed:[PBMError errorWithDescription:@"No HTML in creative data"]];
        return;
    }
    
    //check if we receive vast data instead of banner
    if (html && [self hasVastTag:html]) {
        [self onResolutionFailed:[PBMError errorWithDescription:@"Wrong data format (VAST) detected for display ad request"]];
        return;
    }

    CGRect rect = CGRectMake(0.0, 0.0, self.creativeModel.width, self.creativeModel.height);
    if (!self.prebidWebView) {
        self.prebidWebView = [[PBMWebView alloc] initWithFrame:rect
                                                 creativeModel:self.creativeModel
                                                     targeting:Targeting.shared];
    } else {
        self.prebidWebView.frame = rect;
    }
    
    if (self.creativeModel.isCompanionAd) {
        self.prebidWebView.rewardedAdURL = self.rewardedConfig.endcardEvent;
    } else {
        self.prebidWebView.rewardedAdURL = self.rewardedConfig.bannerEvent;
    }
    
    self.prebidWebView.delegate = self;
    self.view = self.prebidWebView;

    // Signal readiness to the creative factory immediately. HTML is loaded lazily
    // in displayWithRootViewController:, once the view has been added to the hierarchy,
    // so that third-party JS inside the ad markup cannot fire impression trackers
    // before the ad is actually visible.
    [self onResolutionCompleted];
}

- (BOOL)hasVastTag:(NSString *)html {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<(\\s*)VAST(\\s{1,})version(\\s*)=" options:0 error:NULL];
    NSRange range = NSMakeRange(0, html.length);
    NSUInteger numberOfMatches = [regex numberOfMatchesInString:html options:0 range:range];

    return numberOfMatches > 0;
}
                     
 - (id <PBMUIApplicationProtocol>)getApplication {
     return [UIApplication sharedApplication];
 }

- (void)displayWithRootViewController:(UIViewController*)viewController {
    // Load HTML now that the view is in the hierarchy (addSubview: is always called
    // before displayWithRootViewController: in PBMAdViewManager). This ensures
    // third-party JS in the ad markup only executes once the ad is actually being shown.
    [self loadHTMLToWebView];

    //Either these constraints are redundant or the initWithFrame is.
    [self.prebidWebView PBMAddCropAndCenterConstraintsWithInitialWidth:self.prebidWebView.frame.size.width initialHeight:self.prebidWebView.frame.size.height];
    [self.prebidWebView prepareForMRAIDWithRootViewController:viewController];

    [super displayWithRootViewController:viewController];

    if (self.creativeModel.isCompanionAd == YES) {
        [self.eventManager trackEvent:PBMTrackingEventCreativeView];

        // For rewarded we have different logic for display completion.
        // See `setupRewardTimerIfNeeded` for more details
        if (!self.creativeModel.adConfiguration.isRewarded) {
            [self.modalManager creativeDisplayCompleted:self];
        }
    }
    
    [self.viewabilityTracker start];
}

- (void)onAdDisplayed {
    // If OM session hasn't started, hold the impression and other display tracking until the
    // session exists — otherwise super would fire the impression before the OM SDK can record it.
    if (!self.openMeasurementSessionHasStarted && !self.webviewFailedToLoad) {
        self.needsOpenMeasurementSync = YES;
        return;
    }

    [super onAdDisplayed];
    [self setupDisplayTimer];
    [self setupRewardTimerIfNeeded];

    // For html ads, we definitely don't need to keep polling viewability after this point.
    // TODO: For other types of ads I'm not so sure yet
    [self.viewabilityTracker stop];
    self.viewabilityTracker = nil;
}

- (void)setupDisplayTimer {
    //Banners display for a set amount of time and then signal creativeDidComplete.
    //Interstitials display for as long as the user is enjoying their presence.
    if (self.creativeModel.adConfiguration.presentAsInterstitial) {
        return;
    }
        
    NSTimeInterval displayInterval = [[self displayInterval] doubleValue];

    if (displayInterval <= 0) {
        //Treat as "display forever"
        return;
    }
        
    @weakify(self);
    dispatch_after([PBMFunctions dispatchTimeAfterTimeInterval:displayInterval], dispatch_get_main_queue(), ^{
        @strongify(self);
        
        if (!self) { return; }
        //If its open, don't count this as a creativeDidComplete. Re-start the display timer.
        if ([self isOpened]) {
            [self setupDisplayTimer];
        } else {
            [self.creativeViewDelegate creativeDidComplete:self];
        }
    });
}

- (void)setupRewardTimerIfNeeded {
    // NOTE: Rewarded API only
    // Signal to the application that the user has earned the reward after
    // the certain period of time that the ad is on the screen.
    if (!self.creativeModel.adConfiguration.isRewarded) {
        return;
    }
    
    if (!self.rewardedConfig) {
        return;
    }
    
    NSTimeInterval rewardNotificationInterval = 0.0;
    
    if (self.creativeModel.isCompanionAd) {
        NSNumber * videoEndcardTime = self.rewardedConfig.endcardTime;
        NSNumber * defaultEndcardTime = self.rewardedConfig.defaultCompletionTime;
        rewardNotificationInterval = (videoEndcardTime) ? [videoEndcardTime intValue] : [defaultEndcardTime intValue];
    } else {
        NSNumber * bannerEndcardTime = self.rewardedConfig.bannerTime;
        NSNumber * defaultBannerTime = self.rewardedConfig.defaultCompletionTime;
        rewardNotificationInterval = (bannerEndcardTime) ? [bannerEndcardTime intValue] : [defaultBannerTime intValue];
    }
    
    self.backgroundAwareTimer = [PBMBackgroundAwareTimer new];
    
    // Track user did earn reward
    @weakify(self);
    [self.backgroundAwareTimer startTimerWith:rewardNotificationInterval
                                   completion:^{
        @strongify(self);
        
        if (!self) { return; }
        
        if (!self.creativeModel.userHasEarnedReward) {
            self.creativeModel.userHasEarnedReward = YES;
            [self.creativeViewDelegate creativeDidSendRewardedEvent:self];
        }
        
        // Track post reward event
        [self setupPostRewardTimer];
    }];
}

- (void)setupPostRewardTimer {
    // NOTE: Rewarded API only
    // Signal to the SDK about the post reward event in order to execute close ad logic.
    if (!self.creativeModel.adConfiguration.isRewarded) {
        return;
    }
    
    if (!self.rewardedConfig) {
        return;
    }
    
    NSTimeInterval postRewardTime = [self.rewardedConfig.postRewardTime doubleValue] ?: 0;
    
    if (postRewardTime < 0.0 || !self.creativeModel.userHasEarnedReward ||
        self.creativeModel.userPostRewardEventSent) {
        return;
    }
    
    self.backgroundAwareTimer = [PBMBackgroundAwareTimer new];
    
    // Track user did earn reward
    @weakify(self);
    [self.backgroundAwareTimer startTimerWith:postRewardTime
                                   completion:^{
        @strongify(self);
        
        if (!self) { return; }
        
        if (!self.creativeModel.userPostRewardEventSent) {
            self.creativeModel.userPostRewardEventSent = YES;
            [self.modalManager creativeDisplayCompleted:self];
        }
    }];
}


// Per the IAB OM SDK integration guide, the OMIDAdSession must not be created until the WebView has
// finished loading the injected OM SDK JS — creating it sooner leaves verification scripts unable to
// receive impression and other events. The transaction requests session creation as soon as the
// creative is built, which is before the HTML (and its injected OM JS) is loaded lazily in
// displayWithRootViewController:. setupOpenMeasurementSession is a no-op until the WebView has
// finished loading; webViewDidFinishNavigation: then creates the session once loading completes.
- (void)createOpenMeasurementSession {
    if (!NSThread.currentThread.isMainThread) {
        PBMLogError(@"Open Measurement session can only be created on the main thread");
        return;
    }
    [self setupOpenMeasurementSession];
}

- (void)setupOpenMeasurementSession {
    // Create the session exactly once, and only after the WebView has finished loading the injected
    // OM JS — verification scripts can't receive events on a session created any earlier. Both entry
    // points (createOpenMeasurementSession and webViewDidFinishNavigation:) funnel through here.
    if (self.openMeasurementSessionHasStarted || self.prebidWebView.state != PBMWebViewStateLoaded) {
        return;
    }

    self.transaction.measurementSession = [self.transaction.measurementWrapper initializeWebViewSession:self.prebidWebView.internalWebView
                                                                                             contentUrl:@""];
    if (self.transaction.measurementSession && [self.transaction.measurementSession isKindOfClass:PBMOpenMeasurementSession.class]) {
        [self.prebidWebView addFriendlyObstructionsToMeasurementSession:self.transaction.measurementSession];
        [self.transaction.measurementSession start];
    }

    self.openMeasurementSessionHasStarted = YES;

    [self fireDeferredImpressionIfNeeded];
}

// The impression is driven by viewability (onAdDisplayed), which can fire before the OM session has
// started. When that happens onAdDisplayed defers and sets needsOpenMeasurementSync; replay it here
// once the session exists (or once we know the WebView failed to load) so the OM SDK records it.
- (void)fireDeferredImpressionIfNeeded {
    if (self.needsOpenMeasurementSync) {
        self.needsOpenMeasurementSync = NO;
        [self onAdDisplayed];
    }
}

- (void)onWillTrackImpression {
    [super onWillTrackImpression];
    [self.eventManager trackEvent:PBMTrackingEventLoaded];
}

- (void)loadHTMLToWebView {
    
    NSString *html = self.creativeModel.html;
    NSString *htmlWithBodyAndHTMLTags = [PBMHTMLFormatter ensureHTMLHasBodyAndHTMLTags:html];
    
    NSError *error;
    NSString *htmlWithMeasurementJS = [self.transaction.measurementWrapper injectJSLib:htmlWithBodyAndHTMLTags error:&error];
    if (error) {
        PBMLogError(@"PBMWebView can't inject Open Measurement JS lib with error: %@", [error localizedDescription]);
    }
    
    [self.prebidWebView loadHTML:htmlWithMeasurementJS ?: htmlWithBodyAndHTMLTags
                        baseURL:self.baseURL
                  injectMraidJs:YES];
}

#pragma mark - PBMWebViewDelegate

- (void)webViewReadyToDisplay:(PBMWebView *)webView {
    PBMLogInfo(@"PBMWebView is ready to display");
    [self onResolutionCompleted];
}

/**
 The OM session must start only after the WebView has truly finished loading (didFinishNavigation),
 not at the earlier `document.readyState == complete` signal (webViewReadyToDisplay:). OM verification
 scripts load asynchronously and don't register their session observer until navigation completes, so
 starting the session — and firing the deferred impression — any earlier races ahead of them: the
 verification scripts never observe sessionStart/impression and no measurement is reported.
 */
- (void)webViewDidFinishNavigation:(PBMWebView *)webView {
    [self setupOpenMeasurementSession];
}

- (void)webView:(PBMWebView *)webView failedToLoadWithError:(NSError *)error {
    PBMLogError(@"%@", error.localizedDescription);
    self.webviewFailedToLoad = YES;
    [self fireDeferredImpressionIfNeeded];
}

- (void)webView:(PBMWebView *)webView receivedClickthroughLink:(NSURL *)url {
    [self handleClickthrough:url sdkConfiguration:self.sdkConfiguration];
}

- (void)webView:(PBMWebView *)webView receivedMRAIDLink:(NSURL *)url {
    @try {
        if (![self.view isKindOfClass:[PBMWebView class]]) {
            PBMLogWarn(@"Could not cast creative view to PBMWebView");
            return;
        }
        
        if (!self.MRAIDController) {
            self.MRAIDController = [[PBMMRAIDController alloc] initWithCreative:self
                                                    viewControllerForPresenting:self.viewControllerForPresentingModals
                                                                        webView:self.prebidWebView
                                                           creativeViewDelegate:self.creativeViewDelegate
                                                                  downloadBlock:self.downloadBlock];
        }
        [self.MRAIDController webView:webView handleMRAIDURL:url];
    } @catch (NSException *exception) {
        PBMLogWarn(@"%@", [exception reason]);
    }
}

- (void)webView:(PBMWebView *)webView receivedRewardedEventLink:(NSURL *)url {
    if (!self.creativeModel.userHasEarnedReward) {
        [self.creativeViewDelegate creativeDidSendRewardedEvent:self];
        self.creativeModel.userHasEarnedReward = YES;
        
        [self setupPostRewardTimer];
    }
}

#pragma mark - PBMModalManagerDelegate

- (void)modalManagerDidFinishPop:(id<PBMModalState>)state {
    
    // TODO: Refactor
    // This method illustrates very precisely that we should have different creatives
    // for Banner/Interstitial/MRAID ads.
    // We should use OOP approach for logic encapsulation instead of 'if' logic.

    // Clickthrough
    if (self.clickthroughVisible) {
        [self.creativeViewDelegate creativeClickthroughDidClose:self];
        self.clickthroughVisible = NO;
        
        return;
    }
    
    // EndCard
    if (self.creativeModel.isCompanionAd) {
        // Dismiss parent VideoCreative
        PBMVoidBlock dismissParent = [self.transaction getFirstCreative].dismissInterstitialModalState;
        if (dismissParent) {
            dismissParent();
        }
    }
    
    if (self.MRAIDController && self.MRAIDController.isTwoPartExpand) {
        [self.creativeViewDelegate creativeReadyToReimplant:self];
        [self.MRAIDController updateForClose:self.creativeModel.adConfiguration.presentAsInterstitial];
    }

    //Creative presented as Interstitial
    if (self.creativeModel.adConfiguration.presentAsInterstitial) {
        [self.creativeViewDelegate creativeDidComplete:self];
    }
    
    [self.creativeViewDelegate creativeInterstitialDidClose:self];
}

- (void)modalManagerDidLeaveApp:(id<PBMModalState>) state {
    [self.creativeViewDelegate creativeInterstitialDidLeaveApp:self];
}

#pragma mark - Helper Methods

- (void)handleClickthrough:(NSURL*)url
          sdkConfiguration:(Prebid *)sdkConfiguration
         completionHandler:(void (^)(BOOL success))completion
                    onExit:(PBMVoidBlock)onClickthroughExitBlock {
    @weakify(self);
    [super handleClickthrough:url
             sdkConfiguration:self.sdkConfiguration
            completionHandler:^void(BOOL success) {
        @strongify(self);
        if (!self) { return; }
        
        if (success) {
            [self.creativeViewDelegate creativeWasClicked:self];
            if (self.creativeModel.isCompanionAd) {
                [self.eventManager trackEvent:PBMTrackingEventCompanionClick];
            } else {
                [self.eventManager trackEvent:PBMTrackingEventClick];
            }
        }
        
        completion(success);
    } onExit:onClickthroughExitBlock];
}

@end
