#import <Foundation/Foundation.h>
#import "PBMViewExposureChecker.h"

@protocol PBMViewExposure;

NS_ASSUME_NONNULL_BEGIN

typedef void(^Life360ExposureChangeHandler)(id<PBMViewExposure> exposure, NSError * _Nullable error);

/**
 Modified from PBMViewExposureChecker to support scroll based tracking instead of timer based polling
 Also fixes issue where tracking would stop during user touch
 */
@interface Life360ViewExposureChecker : PBMViewExposureChecker

- (instancetype)initWithView:(UIView *)view onExposureChange:(nullable Life360ExposureChangeHandler)onExposureChange;

/// OMID flags any overlapping alpha>0/!hidden view as an occluder, ignoring transparent backgrounds
/// and non-drawing children. This surfaces the views whose entire subtree paints nothing over the ad
/// so callers can register them as OMID friendly obstructions and keep viewability accurate.
- (NSArray<UIView *> *)friendlyObstructionViews;

@end

NS_ASSUME_NONNULL_END
