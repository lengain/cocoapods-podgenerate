#import "PodBase14Utilities.h"

@implementation PodBase14Utilities

+ (NSString *)bundleIdentifier {
    return @"com.example.PodBase14";
}

+ (NSBundle *)resourceBundle {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"PodBase14Resources" ofType:@"bundle"];
    if (path) {
        return [NSBundle bundleWithPath:path];
    }
    return bundle;
}

+ (NSString *)versionString {
    return @"1.0.0";
}

@end
