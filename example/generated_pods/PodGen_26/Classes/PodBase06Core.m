#import "PodBase06Core.h"

@implementation PodBase06Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase06Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
