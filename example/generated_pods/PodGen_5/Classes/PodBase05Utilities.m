#import "PodBase05Utilities.h"

@implementation PodBase05Utilities

+ (NSString *)bundleIdentifier {
    return @"com.example.PodBase05";
}

+ (NSBundle *)resourceBundle {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"PodBase05Resources" ofType:@"bundle"];
    if (path) {
        return [NSBundle bundleWithPath:path];
    }
    return bundle;
}

+ (NSString *)versionString {
    return @"1.0.0";
}

@end
