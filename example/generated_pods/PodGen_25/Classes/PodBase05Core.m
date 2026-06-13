#import "PodBase05Core.h"

@implementation PodBase05Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase05Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
