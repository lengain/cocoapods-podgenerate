#import "PodBase19Core.h"

@implementation PodBase19Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase19Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
