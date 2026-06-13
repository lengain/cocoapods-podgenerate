#import "PodBase10Utilities.h"

@implementation PodBase10Utilities

+ (NSString *)bundleIdentifier {
    return @"com.example.PodBase10";
}

+ (NSBundle *)resourceBundle {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"PodBase10Resources" ofType:@"bundle"];
    if (path) {
        return [NSBundle bundleWithPath:path];
    }
    return bundle;
}

+ (NSString *)versionString {
    return @"1.0.0";
}

@end
