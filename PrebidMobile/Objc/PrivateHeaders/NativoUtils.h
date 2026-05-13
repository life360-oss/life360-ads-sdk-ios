//
//  NativoUtils.h
//  NativoPrebidSDK
//
//  Created by Matthew Murray on 12/11/25.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^Debouncable)(id _Nullable param);

@interface NativoUtils : NSObject

+ (Debouncable)debounceAction:(void (^)(id param))action withInterval:(NSTimeInterval)interval;

+ (UIImageView *)getViewAsImage:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
