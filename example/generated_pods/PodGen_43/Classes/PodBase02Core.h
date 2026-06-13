#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double PodBase02VersionNumber;
FOUNDATION_EXPORT const unsigned char PodBase02VersionString[];

NS_ASSUME_NONNULL_BEGIN

@interface PodBase02Core : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) NSInteger version;

- (instancetype)initWithIdentifier:(NSString *)identifier;
- (NSString *)descriptionString;

@end

NS_ASSUME_NONNULL_END
