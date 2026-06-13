#import "PodBase11Utilities.h"

@implementation PodBase11Utilities

+ (NSString *)bundleIdentifier {
    return @"com.example.PodBase11";
}

+ (NSBundle *)resourceBundle {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"PodBase11Resources" ofType:@"bundle"];
    if (path) {
        return [NSBundle bundleWithPath:path];
    }
    return bundle;
}

+ (NSString *)versionString {
    return @"1.0.0";
}

@end
