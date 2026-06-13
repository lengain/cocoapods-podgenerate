#import "PodBase06AnalyticsTracker.h"

@interface PodBase06AnalyticsTracker ()

@property (nonatomic, strong, readwrite) NSString *name;
@property (nonatomic, assign, readwrite) NSInteger versionCode;

@end

static id _sharedInstance = nil;

@implementation PodBase06AnalyticsTracker

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _name = [name copy];
        _versionCode = 1;
    }
    return self;
}

- (void)configureWithOptions:(nullable NSDictionary *)options {
    if (options) {
        id version = options[@"version"];
        if ([version respondsToSelector:@selector(integerValue)]) {
            _versionCode = [version integerValue];
        }
    }
}

- (void)reset {
    _versionCode = 1;
}

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

@end
