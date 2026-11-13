#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Forward declarations for Netflix types (we'll use id for simplicity)
@protocol NetflixPlayerAccessInfo;
@protocol NetflixPlayerAccessEvent;
@protocol NSError;

// Hook for requestPlayerAccessWithCompletionHandler:
// Original signature: - (void)requestPlayerAccessWithCompletionHandler:(void (^)(id<NetflixPlayerAccessInfo> _Nullable, NSError * _Nullable))completionHandler;
static void (*orig_requestPlayerAccess)(id self, SEL _cmd, void (^completion)(id, id));

static void hooked_requestPlayerAccess(id self, SEL _cmd, void (^completion)(id, id)) {
    NSLog(@"[NetflixBypass] requestPlayerAccessWithCompletionHandler: called - BYPASSING auth");

    // Create a mock NetflixPlayerAccessInfo that indicates success
    // We'll use a simple NSDictionary that mimics the expected structure
    // The actual protocol likely has properties like: isGuest, playerId, accessToken, etc.
    NSDictionary *mockAccessInfo = @{
        @"isGuest": @NO,
        @"playerId": @"offline_player_12345",
        @"accessToken": @"mock_offline_token",
        @"profileId": @"offline_profile",
        @"entitled": @YES,
        @"subscriptionActive": @YES
    };

    // Call completion with success (no error)
    if (completion) {
        completion(mockAccessInfo, nil);
    }
}

// Hook for currentProfileAndReturnError:
// Original signature: - (id)currentProfileAndReturnError:(NSError **)error;
static id (*orig_currentProfile)(id self, SEL _cmd, id *error);

static id hooked_currentProfile(id self, SEL _cmd, id *error) {
    NSLog(@"[NetflixBypass] currentProfileAndReturnError: called - RETURNING mock profile");

    if (error) {
        *error = nil;
    }

    // Return a mock profile dictionary
    return @{
        @"profileId": @"offline_profile",
        @"name": @"Offline Player",
        @"isActive": @YES,
        @"isGuest": @NO,
        @"entitlements": @[@"full_game"],
        @"lastLogin": [NSDate date]
    };
}

// Hook for onPlayerAccessChangeWithAccessEvent:
// Original signature: - (void)onPlayerAccessChangeWithAccessEvent:(id<NetflixPlayerAccessEvent>)event;
static void (*orig_onPlayerAccessChange)(id self, SEL _cmd, id event);

static void hooked_onPlayerAccessChange(id self, SEL _cmd, id event) {
    NSLog(@"[NetflixBypass] onPlayerAccessChangeWithAccessEvent: called - event: %@", event);
    // Just log, don't call original (which might trigger UI)
}

// Constructor function runs when dylib is loaded
__attribute__((constructor))
static void netflix_bypass_init() {
    NSLog(@"[NetflixBypass] Loading Netflix auth bypass dylib...");

    // Wait for NetflixGames framework to load
    // We'll poll for the class to appear
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        Class sdkClass = nil;
        int attempts = 0;
        while (!sdkClass && attempts < 100) {
            sdkClass = objc_getClass("_TtC12NetflixGames15NetflixGamesSDK");
            if (!sdkClass) {
                // Try alternative name
                sdkClass = objc_getClass("NetflixGamesSDK");
            }
            if (!sdkClass) {
                usleep(100000); // 100ms
                attempts++;
            }
        }

        if (!sdkClass) {
            NSLog(@"[NetflixBypass] ERROR: Could not find NetflixGamesSDK class after 10 seconds");
            return;
        }

        NSLog(@"[NetflixBypass] Found NetflixGamesSDK class: %@", sdkClass);

        // Hook requestPlayerAccessWithCompletionHandler:
        SEL sel_request = sel_registerName("requestPlayerAccessWithCompletionHandler:");
        Method origMethod = class_getInstanceMethod(sdkClass, sel_request);
        if (origMethod) {
            orig_requestPlayerAccess = (void *)method_getImplementation(origMethod);
            method_setImplementation(origMethod, (IMP)hooked_requestPlayerAccess);
            NSLog(@"[NetflixBypass] Hooked requestPlayerAccessWithCompletionHandler:");
        } else {
            NSLog(@"[NetflixBypass] WARNING: Could not find requestPlayerAccessWithCompletionHandler: method");
        }

        // Hook currentProfileAndReturnError:
        SEL sel_current = sel_registerName("currentProfileAndReturnError:");
        Method currentMethod = class_getInstanceMethod(sdkClass, sel_current);
        if (currentMethod) {
            orig_currentProfile = (id (*)(id, SEL, id *))method_getImplementation(currentMethod);
            method_setImplementation(currentMethod, (IMP)hooked_currentProfile);
            NSLog(@"[NetflixBypass] Hooked currentProfileAndReturnError:");
        } else {
            NSLog(@"[NetflixBypass] WARNING: Could not find currentProfileAndReturnError: method");
        }

        // Hook onPlayerAccessChangeWithAccessEvent:
        SEL sel_change = sel_registerName("onPlayerAccessChangeWithAccessEvent:");
        Method changeMethod = class_getInstanceMethod(sdkClass, sel_change);
        if (changeMethod) {
            orig_onPlayerAccessChange = (void *)method_getImplementation(changeMethod);
            method_setImplementation(changeMethod, (IMP)hooked_onPlayerAccessChange);
            NSLog(@"[NetflixBypass] Hooked onPlayerAccessChangeWithAccessEvent:");
        } else {
            NSLog(@"[NetflixBypass] WARNING: Could not find onPlayerAccessChangeWithAccessEvent: method");
        }

        NSLog(@"[NetflixBypass] All hooks installed successfully!");
    });
}