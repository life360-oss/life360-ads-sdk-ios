    
#import <Foundation/Foundation.h>
#import "PBMParameterBuilderProtocol.h"
#import "PBMBundleProtocol.h"

@class AdUnitConfig;

NS_ASSUME_NONNULL_BEGIN

@interface NativoParameterBuilder : NSObject <PBMParameterBuilder>

- (instancetype)init NS_UNAVAILABLE;

/// Uses `NSBundle.mainBundle` to resolve the app bundle identifier sent in the request.
- (instancetype)initWithAdConfiguration:(AdUnitConfig *)adConfiguration;

/// The bundle override exists so tests can supply a mock identifier; production always uses `NSBundle.mainBundle`.
- (instancetype)initWithAdConfiguration:(AdUnitConfig *)adConfiguration
                                 bundle:(id<PBMBundleProtocol>)bundle NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
