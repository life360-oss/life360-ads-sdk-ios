//
//  Life360Utils.m
//  Life360AdsSDK
//
//  Created by Matthew Murray on 12/11/25.
//

#import "Life360Utils.h"

NS_ASSUME_NONNULL_BEGIN

@implementation Life360Utils

+ (Debouncable)debounceAction:(void (^)(id param))action withInterval:(NSTimeInterval)interval {
    __block BOOL shouldFire = YES;
    int64_t dispatchDelay = (int64_t)(interval * NSEC_PER_SEC);
    return ^(id param) {
        if (shouldFire) {
            shouldFire = NO;
            action(param);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, dispatchDelay), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                shouldFire = YES;
            });
        }
    };
}

+ (UIImageView *)getViewAsImage:(UIView *)view {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds];
    
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        // Renders the view layer into the context
        [view.layer renderInContext:rendererContext.CGContext];
    }];
    return [[UIImageView alloc] initWithImage:image];
}


@end

NS_ASSUME_NONNULL_END
