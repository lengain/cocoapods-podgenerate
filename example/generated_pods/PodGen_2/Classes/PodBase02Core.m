#import "PodBase02Core.h"

@implementation PodBase02Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase02Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
