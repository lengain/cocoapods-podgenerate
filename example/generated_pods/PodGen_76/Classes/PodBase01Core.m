#import "PodBase01Core.h"

@implementation PodBase01Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase01Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
