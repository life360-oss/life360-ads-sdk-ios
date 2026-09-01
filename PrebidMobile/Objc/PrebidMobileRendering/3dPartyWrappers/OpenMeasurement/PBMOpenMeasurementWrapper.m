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

#import "PBMFunctions.h"
#import "PBMFunctions+Private.h"
#import "PBMMacros.h"
#import "PBMOpenMeasurementWrapper.h"
#import "Log+Extensions.h"

#import "SwiftImport.h"

#import <OMSDK_Life360/OMIDAdSession.h>
#import <OMSDK_Life360/OMIDScriptInjector.h>
#import <OMSDK_Life360/OMIDPartner.h>
#import <OMSDK_Life360/OMIDSDK.h>

#pragma mark - Constants

static NSString * const PBMOpenMeasurementPartnerName   = @"Life360";
static NSString * const PBMOpenMeasurementCustomRefId   = @"";

#pragma mark - Private Interface

@interface PBMOpenMeasurementWrapper ()

@property (nonatomic, readonly) NSString *partnerName;
@property (nonatomic, readonly) NSString *customRefId;

@property (nonatomic, strong, nonnull) OMIDLife360Partner *partner;

@property (nonatomic, strong, nullable) PrebidJSLibraryManager *libraryManager;

@end

#pragma mark - Implementation

@implementation PBMOpenMeasurementWrapper

#pragma mark - Initialization

+ (void)load {
    (void)[PBMOpenMeasurementWrapper shared];
}

+ (instancetype)shared {
    static PBMOpenMeasurementWrapper *shared;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PBMOpenMeasurementWrapper alloc] init];
    });
    
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _libraryManager = PrebidJSLibraryManager.shared;
        [self initializeOMSDK];

        // The Swift half of the SDK can't name this class — under SwiftPM the dependency runs the other
        // way — so publish ourselves for the Swift-side native display path to pick up by protocol.
        [PBMOMSessionWrapperRegistry register:self];
    }
    
    return self;
}

#pragma mark - Properties

- (NSString *)partnerName {
    return PBMOpenMeasurementPartnerName;
}

- (NSString *)customRefId {
    return PBMOpenMeasurementCustomRefId;
}

#pragma mark - PBMMeasurementProtocol

- (nullable NSString *)injectJSLib:(NSString *)html error:(NSError **)error {
    if (!html) {
        [PBMError createError:error description:@"Empty ad's html"];
        return nil;
    }
    
    NSString *jsLib = [self fetchOMSDKScript];
    
    if (!jsLib) {
        [PBMError createError:error description:@"The js lib for Open Measurement is not loaded."];
        return nil;
    }
    
    NSString *res = [OMIDLife360ScriptInjector injectScriptContent:jsLib
                                                            intoHTML:html
                                                               error:error];
    
    return res;
}

- (nullable PBMOpenMeasurementSession *)initializeWebViewSession:(WKWebView *)webView
                                                       contentUrl:(NSString *)contentUrl
                                                isJSBasedTracking:(BOOL)isJSBasedTracking {

    NSError *contextError;
    OMIDLife360AdSessionContext *context = [[OMIDLife360AdSessionContext alloc] initWithPartner:self.partner
                                                                                            webView:webView
                                                                                         contentUrl:contentUrl
                                                                          customReferenceIdentifier:self.customRefId
                                                                                              error:&contextError];

    if (contextError) {
        PBMLogError(@"Unable to create Open Measurement session context with error: %@", [contextError localizedDescription]);
        return nil;
    }

    NSError *configurationError;

    OMIDLife360AdSessionConfiguration *config;
    if (isJSBasedTracking) {
        // stpVideo/ctpVideo banners embed a <video> element and fire its OM events from their own JS, so
        // OM must attribute impression/media events to the JS layer rather than to native.
        config = [[OMIDLife360AdSessionConfiguration alloc]
         initWithCreativeType:OMIDCreativeTypeDefinedByJavaScript
         impressionType:OMIDImpressionTypeDefinedByJavaScript
         impressionOwner:OMIDJavaScriptOwner
         mediaEventsOwner:OMIDJavaScriptOwner
         isolateVerificationScripts:NO
                  error:&configurationError];
    } else {
        config = [[OMIDLife360AdSessionConfiguration alloc]
         initWithCreativeType:OMIDCreativeTypeHtmlDisplay
         impressionType:OMIDImpressionTypeOnePixel
         impressionOwner:OMIDNativeOwner
         mediaEventsOwner:OMIDNoneOwner
         isolateVerificationScripts:NO
         error:&configurationError];
    }

    if (configurationError) {
        PBMLogError(@"Unable to create Open Measurement session configuration with error: %@", [configurationError localizedDescription]);
        return nil;
    }
    
    NSError *sessionError;
    PBMOpenMeasurementSession *session = [[PBMOpenMeasurementSession alloc] initWithContext:context configuration:config isJSBasedTracking:isJSBasedTracking];
    if (!session) {
        PBMLogError(@"Unable to create Open Measurement session with error: %@", [sessionError localizedDescription]);
        return nil;
    }

    [session setupMainView:webView];
    
    return session;
}

- (PBMOpenMeasurementSession *)initializeNativeVideoSession:(UIView *)videoView
                                     verificationParameters:(PBMVideoVerificationParameters *)verificationParameters {
    
    NSString *jsLib = [self fetchOMSDKScript];
    
    if (!jsLib) {
        PBMLogError(@"Open Measurement SDK can't work without valid js script");
        return nil;
    }
    
    NSError *contextError;
    OMIDLife360AdSessionContext *context = [[OMIDLife360AdSessionContext alloc] initWithPartner:self.partner
                                                                                             script:jsLib
                                                                                          resources:[self getScriptResources:verificationParameters]
                                                                                         contentUrl:nil
                                                                          customReferenceIdentifier:nil
                                                                                              error:&contextError];
    if (contextError) {
        PBMLogError(@"Unable to create Open Measurement session context with error: %@", [contextError localizedDescription]);
        return nil;
    }
    
    NSError *configurationError;
    
    OMIDLife360AdSessionConfiguration *config = [[OMIDLife360AdSessionConfiguration alloc] initWithCreativeType:OMIDCreativeTypeVideo
                                                                                                     impressionType:OMIDImpressionTypeOnePixel
                                                                                                    impressionOwner:OMIDNativeOwner
                                                                                                   mediaEventsOwner:OMIDNativeOwner
                                                                                         isolateVerificationScripts:NO
                                                                                                              error:&configurationError];
    if (configurationError) {
        PBMLogError(@"Unable to create Open Measurement session configuration with error: %@", [configurationError localizedDescription]);
        return nil;
    }
    
    NSError *sessionError;
    PBMOpenMeasurementSession *session = [[PBMOpenMeasurementSession alloc] initWithContext:context configuration:config isJSBasedTracking:NO];
    if (!session) {
        PBMLogError(@"Unable to create Open Measurement session with error: %@", [sessionError localizedDescription]);
        return nil;
    }

    [session setupMainView:videoView];
    
    return session;
}

- (PBMOpenMeasurementSession *)initializeNativeDisplaySession:(UIView *)view
                                                    omidJSUrl:(NSString *)omidJSUrl
                                                    vendorKey:(NSString *)vendorKey
                                                   parameters:(NSString *)verificationParameters {
    
    NSString *jsLib = [self fetchOMSDKScript];
    
    if (!jsLib) {
        PBMLogError(@"Open Measurement SDK can't work without valid js script");
        return nil;
    }
    
    NSArray<OMIDLife360VerificationScriptResource *> *resources = [self scriptResourcesFrom:omidJSUrl
                                                                                    vendorKey:vendorKey
                                                                                   parameters:verificationParameters];
    NSError *contextError;
    OMIDLife360AdSessionContext *context = [[OMIDLife360AdSessionContext alloc] initWithPartner:self.partner
                                                                                             script:jsLib
                                                                                          resources:resources
                                                                                         contentUrl:nil
                                                                          customReferenceIdentifier:nil
                                                                                              error:&contextError];
    if (contextError) {
        PBMLogError(@"Unable to create Open Measurement session context with error: %@",
                    [contextError localizedDescription]);
        return nil;
    }
    
    NSError *configurationError;
    
    // TODO: revisit impressionType. NativeAd only fires the impression once the registered view has been
    // at least half visible for a full second, which is a viewable impression rather than a one-pixel one.
    OMIDLife360AdSessionConfiguration *config = [
        [OMIDLife360AdSessionConfiguration alloc]
        initWithCreativeType:OMIDCreativeTypeNativeDisplay
        impressionType:OMIDImpressionTypeOnePixel
        impressionOwner:OMIDNativeOwner
        mediaEventsOwner:OMIDNoneOwner
        isolateVerificationScripts:NO
        error:&configurationError];
    
    if (configurationError) {
        PBMLogError(@"Unable to create Open Measurement session configuration with error: %@",
                    [configurationError localizedDescription]);
        return nil;
    }
    
    NSError *sessionError;
    PBMOpenMeasurementSession *session = [[PBMOpenMeasurementSession alloc] initWithContext:context configuration:config isJSBasedTracking:NO];
    if (!session) {
        PBMLogError(@"Unable to create Open Measurement session with error: %@", [sessionError localizedDescription]);
        return nil;
    }

    [session setupMainView:view];
    
    return session;
}


#pragma mark - Internal Methods

- (void)initializeOMSDK {
    NSError *error;
    BOOL sdkStarted = [[OMIDLife360SDK sharedInstance] activate];
    
    if (!sdkStarted) {
        PBMLogError(@"Life360 SDK can't initialize Open Measurement SDK with error: %@", [error localizedDescription]);
    }
    
    self.partner = [[OMIDLife360Partner alloc] initWithName:self.partnerName
                                                versionString:[PBMFunctions sdkVersion]];
}

-(nullable NSString*)fetchOMSDKScript {
    return [self.libraryManager getOMSDKLibrary];;
}

- (nonnull NSArray<OMIDLife360VerificationScriptResource *> *)getScriptResources:(PBMVideoVerificationParameters *)vastVerificationParamaters {
    NSMutableArray *scripts = [NSMutableArray new];
    
    for (PBMVideoVerificationResource *vastResource in vastVerificationParamaters.verificationResources) {
        if (!(vastResource.url && vastResource.vendorKey && vastResource.params)) {
            PBMLogError(@"Invalid Verification Resource. All properties should be provided. Url: %@, vendorKey: %@, params: %@", vastResource.url, vastResource.vendorKey, vastResource.params);
            continue;
        }
        
        NSURL *url = [[NSURL alloc] initWithString:vastResource.url];
        if (!url) {
            PBMLogError(@"The URL for OM Verification Resource is invalid. Url: %@", vastResource.url);
            continue;
        }
        
        OMIDLife360VerificationScriptResource *resource = [[OMIDLife360VerificationScriptResource alloc] initWithURL:url
                                                                                                               vendorKey:vastResource.vendorKey
                                                                                                              parameters:vastResource.params];
        
        if (!resource) {
            PBMLogError(@"Can't create OM Verification Resource. Url: %@, vendorKey: %@, params: %@", vastResource.url, vastResource.vendorKey, vastResource.params);
            continue;
        }
        
        [scripts addObject:resource];
    }
    
    return scripts;
}

- (nonnull NSArray<OMIDLife360VerificationScriptResource *> *)scriptResourcesFrom:(NSString *)omidJSUrl
                                                                          vendorKey:(NSString *)vendorKey
                                                                         parameters:(NSString *)parameters {
    
    if (!omidJSUrl || !vendorKey || !parameters) {
        PBMLogError(@"Invalid Verification Resource. All properties should be provided. Url: %@, vendorKey: %@, params: %@",
                    omidJSUrl, vendorKey, parameters);
        return @[];
    }
    
    NSURL *url = [[NSURL alloc] initWithString:omidJSUrl];
    if (!url) {
        PBMLogError(@"The URL for OM Verification Resource is invalid. Url: %@", omidJSUrl);
        return @[];
    }
    
    OMIDLife360VerificationScriptResource *resource = [[OMIDLife360VerificationScriptResource alloc] initWithURL:url
                                                                                                           vendorKey:vendorKey
                                                                                                          parameters:parameters];
    
    if (!resource) {
        PBMLogError(@"Can't create OM Verification Resource. Url: %@, vendorKey: %@, params: %@",
                    omidJSUrl, vendorKey, parameters);
        return @[];
    }
    
    return  @[resource];
}

@end
