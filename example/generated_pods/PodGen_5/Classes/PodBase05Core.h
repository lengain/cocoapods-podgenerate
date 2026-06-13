#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double PodBase05VersionNumber;
FOUNDATION_EXPORT const unsigned char PodBase05VersionString[];

NS_ASSUME_NONNULL_BEGIN

@interface PodBase05Core : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) NSInteger version;

- (instancetype)initWithIdentifier:(NSString *)identifier;
- (NSString *)descriptionString;

@end

NS_ASSUME_NONNULL_END
