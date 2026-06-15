#import "FlutterEngine.h"
@implementation FlutterEngine
+ (instancetype)sharedEngine { static id s; s = [[self alloc] init]; return s; }
- (void)run { }
@end
