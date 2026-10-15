//
//  Life360Utils.m
//  Life360AdsSDK
//
//  Created by Matthew Murray on 12/11/25.
//

#import "Life360Utils.h"

NS_ASSUME_NONNULL_BEGIN

@implementation Life360Utils

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
