#import "PodBase17Utilities.h"

@implementation PodBase17Utilities

+ (NSString *)bundleIdentifier {
    return @"com.example.PodBase17";
}

+ (NSBundle *)resourceBundle {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"PodBase17Resources" ofType:@"bundle"];
    if (path) {
        return [NSBundle bundleWithPath:path];
    }
    return bundle;
}

+ (NSString *)versionString {
    return @"1.0.0";
}

@end
