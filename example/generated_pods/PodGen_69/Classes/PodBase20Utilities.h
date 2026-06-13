#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PodBase20Utilities : NSObject

+ (NSString *)bundleIdentifier;
+ (NSBundle *)resourceBundle;
+ (nullable NSString *)versionString;

@end

NS_ASSUME_NONNULL_END
