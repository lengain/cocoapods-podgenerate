#import "PodBase04Core.h"

@implementation PodBase04Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase04Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
