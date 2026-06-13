#import "PodBase08Core.h"

@implementation PodBase08Core

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _version = 1;
    }
    return self;
}

- (NSString *)descriptionString {
    return [NSString stringWithFormat:@"<PodBase08Core: %@ v%ld>", self.identifier, (long)self.version];
}

@end
