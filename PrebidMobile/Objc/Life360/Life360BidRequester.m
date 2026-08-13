// SwiftImport.h pulls in the generated Swift header that defines
// @objc(PBMBidRequesterProtocol). It must precede Life360BidRequester.h so the
// protocol is fully defined where the @interface declares conformance to it.
#import "SwiftImport.h"

#import "Life360BidRequester.h"

#import "PBMBidResponseTransformer.h"
#import "PBMPrebidParameterBuilder.h"
#import "PBMParameterBuilderService.h"
#import "Life360ParameterBuilder.h"
#import "Life360GeoLocationParameterBuilder.h"
#import "Log+Extensions.h"
#import "PBMMacros.h"

@interface Life360BidRequester () <PBMBidRequester>

@property (nonatomic, strong, nonnull, readonly) id<PrebidServerConnectionProtocol> connection;
@property (nonatomic, strong, nonnull, readonly) Prebid *sdkConfiguration;
@property (nonatomic, strong, nonnull, readonly) Targeting *targeting;
@property (nonatomic, strong, nonnull, readonly) AdUnitConfig *adUnitConfiguration;

/// Guarded by `@synchronized(self)`; take it through `-claimCompletion` rather than reading directly.
@property (nonatomic, copy, nullable) void (^completion)(BidResponse *, NSError *);

- (void)makeRequestWithCompletion:(void (^)(BidResponse *, NSError *))completion;
- (nullable void (^)(BidResponse *, NSError *))claimCompletion;

@end

@implementation Life360BidRequester

- (instancetype)initWithConnection:(id<PrebidServerConnectionProtocol>)connection
                  sdkConfiguration:(Prebid *)sdkConfiguration
                         targeting:(Targeting *)targeting
               adUnitConfiguration:(AdUnitConfig *)adUnitConfiguration {
    if (!(self = [super init])) {
        return nil;
    }
    _connection = connection;
    _sdkConfiguration = sdkConfiguration;
    _targeting = targeting;
    _adUnitConfiguration = adUnitConfiguration;
    return self;
}

- (void)requestBidsWithCompletion:(void (^)(BidResponse * _Nullable, NSError * _Nullable))completion {
    @weakify(self);
    // Warm the same UA service the request body reads from (see -buildORTBRequestString) before
    // building it. The service resolves the user agent through a web view on the main thread, so
    // building first puts an empty device.ua on the first request of a session.
    [self.connection.userAgentService fetchUserAgentWithCompletion:^(NSString * _Nonnull userAgent) {
        @strongify(self);
        [self makeRequestWithCompletion:completion];
    }];
}

- (void)makeRequestWithCompletion:(void (^)(BidResponse * _Nullable, NSError * _Nullable))completion {
    // Claim the completion slot atomically, so two callers cannot both believe they own this request.
    @synchronized(self) {
        if (self.completion) {
            completion(nil, [PBMError requestInProgress]);
            return;
        }
        self.completion = completion ?: ^(BidResponse *r, NSError *e) {};
    }

    NSString * const requestString = [self buildORTBRequestString];
    if (requestString.length == 0) {
        void (^ const done)(BidResponse *, NSError *) = [self claimCompletion];
        if (done) {
            done(nil, [PBMError errorWithDescription:@"Failed to build ORTB request"]);
        }
        return;
    }

    NSData *rtbRequestData = [requestString dataUsingEncoding:NSUTF8StringEncoding];

    const NSInteger rawTimeoutMS = self.sdkConfiguration.timeoutMillis;
    NSNumber * const dynamicTimeout = self.sdkConfiguration.timeoutMillisDynamic;

    // Both sources hold milliseconds; the connection wants seconds.
    const NSTimeInterval postTimeout = (dynamicTimeout
                                        ? dynamicTimeout.doubleValue / 1000.0
                                        : rawTimeoutMS / 1000.0);

    // Fixed Life360 endpoint
    NSString * const life360URL = @"https://exchange.postrelease.com/esi.json?ntv_epid=54";

    @weakify(self);
    [self.connection post:life360URL
                     data:rtbRequestData
                  timeout:postTimeout
                 callback:^(PrebidServerResponse * _Nonnull serverResponse) {
        @strongify(self);
        if (!self) { return; }

        void (^ const done)(BidResponse *, NSError *) = [self claimCompletion];
        if (!done) {
            // Redirects, retries and network-stack bugs can fire this callback more than once. The
            // completion advances the ad load flow state machine, so it must run exactly once.
            PBMLogInfo(@"Life360 bid callback invoked more than once. Ignoring the duplicate.");
            return;
        }

        if (serverResponse.statusCode == 204) {
            done(nil, [PBMError blankResponse]);
            return;
        }

        if (serverResponse.error) {
            done(nil, serverResponse.error);
            return;
        }

        NSError *transformError = nil;
        Life360BidResponse * const bidResponse = [[Life360BidResponse alloc] initWithJsonDictionary:serverResponse.jsonDict];
        done(bidResponse, transformError);
    }];
}

/// Takes ownership of the pending completion, or returns nil if it has already been taken.
/// The caller owns the returned block and must invoke it exactly once.
- (nullable void (^)(BidResponse *, NSError *))claimCompletion {
    @synchronized(self) {
        void (^ const done)(BidResponse *, NSError *) = self.completion;
        self.completion = nil;
        return done;
    }
}

- (NSString *)buildORTBRequestString {
    PBMPrebidParameterBuilder * const prebidParamsBuilder =
    [[PBMPrebidParameterBuilder alloc] initWithAdConfiguration:self.adUnitConfiguration
                                              sdkConfiguration:self.sdkConfiguration
                                                     targeting:self.targeting
                                              userAgentService:self.connection.userAgentService];
    
    // this will add tagid and any other needed params for Life360
    Life360ParameterBuilder * life360ParamsBuilder = [[Life360ParameterBuilder alloc] initWithAdConfiguration:self.adUnitConfiguration];
    
    // Add geo location if opted in
    Life360GeoLocationParameterBuilder *geoBuilder = [[Life360GeoLocationParameterBuilder alloc] initWithLocationManager:PBMLocationManager.shared];

    NSDictionary<NSString *, NSString *> * const params =
    [PBMParameterBuilderService buildParamsDictWithAdConfiguration:self.adUnitConfiguration.adConfiguration
                                           extraParameterBuilders:@[prebidParamsBuilder, life360ParamsBuilder, geoBuilder]];

    return params[@"openrtb"] ?: @"";
}

@end
