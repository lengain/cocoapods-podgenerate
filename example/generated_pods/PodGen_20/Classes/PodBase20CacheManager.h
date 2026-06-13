#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PodBase20CacheManager : NSObject

@property (nonatomic, strong, readonly) NSString *name;
@property (nonatomic, assign, readonly) NSInteger versionCode;

- (instancetype)initWithName:(NSString *)name;
- (void)configureWithOptions:(nullable NSDictionary *)options;
- (void)reset;
+ (instancetype)shared;

@end

NS_ASSUME_NONNULL_END
