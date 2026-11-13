#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdarg.h>
#import <time.h>
#import <stdlib.h>

@protocol NetflixPlayerAccessInfo;
@protocol NetflixPlayerAccessEvent;
@protocol NSError;

// ========== FORWARD DECLARATIONS ==========
static void install_hooks(Class sdkClass);
static Class find_netflix_sdk_class(void);

// ========== FILE LOGGING ==========
static inline void bypass_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);

    @autoreleasepool {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            NSString *docPath = paths[0];
            NSString *logPath = [docPath stringByAppendingPathComponent:@"bypass_debug.log"];

            FILE *f = fopen([logPath UTF8String], "a");
            if (f) {
                time_t now = time(NULL);
                struct tm *tm_info = localtime(&now);
                char timestamp[32];
                strftime(timestamp, sizeof(timestamp), "%H:%M:%S", tm_info);
                fprintf(f, "[%s] ", timestamp);
                vfprintf(f, fmt, args);
                fprintf(f, "\n");
                fclose(f);
            }
        }
    }
    va_end(args);
}

#define BYPASS_LOG(fmt, ...) do { \
    bypass_log(fmt, ##__VA_ARGS__); \
    fprintf(stderr, "[BYPASS] " fmt "\n", ##__VA_ARGS__); \
} while(0)

// ========== HOOKS ==========
static void (*orig_requestPlayerAccess)(id self, SEL _cmd, void (^completion)(id, id));

static void hooked_requestPlayerAccess(id self, SEL _cmd, void (^completion)(id, id)) {
    BYPASS_LOG("requestPlayerAccessWithCompletionHandler: called - BYPASSING auth");

    NSDictionary *mockAccessInfo = @{
        @"isGuest": @NO,
        @"playerId": @"offline_player_12345",
        @"accessToken": @"mock_offline_token",
        @"profileId": @"offline_profile",
        @"entitled": @YES,
        @"subscriptionActive": @YES
    };

    if (completion) {
        completion(mockAccessInfo, nil);
    }
}

static id (*orig_currentProfile)(id self, SEL _cmd, id *error);

static id hooked_currentProfile(id self, SEL _cmd, id *error) {
    BYPASS_LOG("currentProfileAndReturnError: called - RETURNING mock profile");

    if (error) {
        *error = nil;
    }

    return @{
        @"profileId": @"offline_profile",
        @"name": @"Offline Player",
        @"isActive": @YES,
        @"isGuest": @NO,
        @"entitlements": @[@"full_game"],
        @"lastLogin": [NSDate date]
    };
}

static void (*orig_onPlayerAccessChange)(id self, SEL _cmd, id event);

static void hooked_onPlayerAccessChange(id self, SEL _cmd, id event) {
    BYPASS_LOG("onPlayerAccessChangeWithAccessEvent: called - event: %p", event);
}

// ========== CLASS FINDER ==========
static Class find_netflix_sdk_class(void) {
    const char *candidates[] = {
        "_TtC12NetflixGames15NetflixGamesSDK",
        "_TtC12NetflixGames14NetflixGamesSDK",
        "_TtC12NetflixGames05SDKC",
        "NetflixGamesSDK",
        "NGPNetflixGamesSDK",
        "NetflixSDK",
        NULL
    };

    for (int i = 0; candidates[i]; i++) {
        Class cls = objc_getClass(candidates[i]);
        if (cls) {
            BYPASS_LOG("Found class: %s", candidates[i]);
            return cls;
        }
    }

    int count = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(count * sizeof(Class));
    count = objc_getClassList(classes, count);

    for (int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (strstr(name, "Netflix") && (strstr(name, "SDK") || strstr(name, "Games"))) {
            BYPASS_LOG("Found via enumeration: %s", name);
            free(classes);
            return classes[i];
        }
    }

    free(classes);
    return nil;
}

// ========== HOOK INSTALLER ==========
static void install_hooks(Class sdkClass) {
    BYPASS_LOG("Installing hooks on class: %s", class_getName(sdkClass));

    SEL sel1 = sel_registerName("requestPlayerAccessWithCompletionHandler:");
    Method m1 = class_getInstanceMethod(sdkClass, sel1);
    if (m1) {
        orig_requestPlayerAccess = (void *)method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hooked_requestPlayerAccess);
        BYPASS_LOG("Hooked: requestPlayerAccessWithCompletionHandler:");
    } else {
        BYPASS_LOG("NOT FOUND: requestPlayerAccessWithCompletionHandler:");
    }

    SEL sel2 = sel_registerName("currentProfileAndReturnError:");
    Method m2 = class_getInstanceMethod(sdkClass, sel2);
    if (m2) {
        orig_currentProfile = (id (*)(id, SEL, id *))method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hooked_currentProfile);
        BYPASS_LOG("Hooked: currentProfileAndReturnError:");
    } else {
        BYPASS_LOG("NOT FOUND: currentProfileAndReturnError:");
    }

    SEL sel3 = sel_registerName("onPlayerAccessChangeWithAccessEvent:");
    Method m3 = class_getInstanceMethod(sdkClass, sel3);
    if (m3) {
        orig_onPlayerAccessChange = (void *)method_getImplementation(m3);
        method_setImplementation(m3, (IMP)hooked_onPlayerAccessChange);
        BYPASS_LOG("Hooked: onPlayerAccessChangeWithAccessEvent:");
    } else {
        BYPASS_LOG("NOT FOUND: onPlayerAccessChangeWithAccessEvent:");
    }

    BYPASS_LOG("Hook installation complete");
}

// ========== CONSTRUCTOR ==========
__attribute__((constructor(101)))
static void bypass_init(void) {
    BYPASS_LOG("=== bypass.dylib LOADED ===");

    Class sdkClass = find_netflix_sdk_class();

    if (sdkClass) {
        install_hooks(sdkClass);
    } else {
        BYPASS_LOG("Class not found immediately, will retry in background...");

        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_async(queue, ^{
            int attempts = 0;
            Class cls = nil;
            while (!cls && attempts < 200) {
                cls = find_netflix_sdk_class();
                if (!cls) {
                    usleep(100000);
                    attempts++;
                }
            }
            if (cls) {
                install_hooks(cls);
            } else {
                BYPASS_LOG("ERROR: NetflixGamesSDK class NOT FOUND after 20 seconds");
            }
        });
    }
}