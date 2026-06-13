#import "PodBase20Core.h"

@implementation PodBase20Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase20Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
