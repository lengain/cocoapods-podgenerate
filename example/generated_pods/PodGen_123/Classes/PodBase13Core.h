#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double PodBase13VersionNumber;
FOUNDATION_EXPORT const unsigned char PodBase13VersionString[];

NS_ASSUME_NONNULL_BEGIN

@interface PodBase13Core : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) NSInteger version;

- (instancetype)initWithIdentifier:(NSString *)identifier;
- (NSString *)descriptionString;

@end

NS_ASSUME_NONNULL_END
